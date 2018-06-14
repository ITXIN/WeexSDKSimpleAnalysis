/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 * 
 *   http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

#import "WXJSCoreBridge.h"
#import "WXDefine.h"
#import "WXAssert.h"
#import "WXLog.h"
#import "WXDefine.h"
#import "WXUtility.h"
#import "WXSDKEngine.h"
#import "WXSDKError.h"
#import <sys/utsname.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import "JSValue+Weex.h"
#import "WXSDKManager.h"
#import "WXExtendCallNativeManager.h"
#import "WXTracingManager.h"
#import "WXExceptionUtils.h"
#import "WXBridgeContext.h"
#import "WXMonitor.h"
#import "WXPolyfillSet.h"
#import "WXAppMonitorProtocol.h"
#import "JSContext+Weex.h"

#import <dlfcn.h>

#import <mach/mach.h>

@interface WXJSCoreBridge ()
{
    NSString * _weexInstanceId;
}

@property (nonatomic, strong)  JSContext *jsContext;
@property (nonatomic, strong)  NSMutableArray *timers;
@property (nonatomic, strong)  NSMutableDictionary *intervaltimers;
@property (nonatomic)  long long intervalTimerId;
@property (nonatomic, strong)  NSMutableDictionary *callbacks;

@end

@implementation WXJSCoreBridge

- (instancetype)init
{
    self = [super init];
    
    if(self){
        _jsContext = [[JSContext alloc] init];
        if (WX_SYS_VERSION_GREATER_THAN_OR_EQUAL_TO(@"8.0")) {
            _jsContext.name = @"Weex Context";
        }
        _timers = [NSMutableArray new];
        _callbacks = [NSMutableDictionary new];
        _intervalTimerId = 0;
        _intervaltimers = [NSMutableDictionary new];
        _multiContext = NO;

        __weak typeof(self) weakSelf = self;
        
        [WXBridgeContext mountContextEnvironment:_jsContext];
        
        _jsContext[@"setTimeout"] = ^(JSValue *function, JSValue *timeout) {
            // this setTimeout is used by internal logic in JS framework, normal setTimeout called by users will call WXTimerModule's method;
            [weakSelf performSelector: @selector(triggerTimeout:) withObject:^() {
                [function callWithArguments:@[]];
            } afterDelay:[timeout toDouble] / 1000];
        };
        
        _jsContext[@"setTimeoutWeex"] = ^(JSValue *appId, JSValue *ret,JSValue *arg ) {
            [weakSelf triggerTimeout:[appId toString] ret:[ret toString] arg:[arg toString]];
        };
        
        _jsContext[@"setIntervalWeex"] = ^(JSValue *appId, JSValue *function,JSValue *arg) {
            return [weakSelf triggerInterval:[appId toString] function:^() {
                [function callWithArguments:@[]];
            } arg:[arg toString]];
        };
        
        _jsContext[@"clearIntervalWeex"] = ^(JSValue *appId, JSValue *ret,JSValue *arg) {
            
            [weakSelf triggerClearInterval:[appId toString] ret:[[ret toNumber] longLongValue]];
        };
        
        _jsContext[@"clearTimeoutWeex"] = ^(JSValue *ret) {
            [weakSelf triggerClearTimeout:[ret toString]];
        };
        
        _jsContext[@"extendCallNative"] = ^(JSValue *value ) {
            return [weakSelf extendCallNative:[value toDictionary]];
        };
    }
    return self;
}

- (void)dealloc
{
    _jsContext.instanceId = nil;
}

- (void)setJSContext:(JSContext *)context
{
    _jsContext = context;
}

- (JSContext *)javaScriptContext
{
    return _jsContext;
}

- (NSString *)weexInstanceId
{
    return _weexInstanceId;
}

- (void)setWeexInstanceId:(NSString *)weexInstanceId
{
    _jsContext.instanceId = weexInstanceId;
    _weexInstanceId = weexInstanceId;
}

#pragma mark - WXBridgeProtocol
/*
 加载JSFramework的核心代码在这里，通过JSContext执行evaluateScript:来加载JSFramework。由于这里并没有返回值，所以加载的JSFramework的目的仅仅是声明了里面的所有方法，并没有调用。这也符合OC加载其他Framework的过程，加载只是加载到内存中，Framework里面的方法可以随时被调用，而不是一加载就调用其所有的方法。
 */
- (void)executeJSFramework:(NSString *)frameworkScript
{
    WXAssertParam(frameworkScript);
    if (WX_SYS_VERSION_GREATER_THAN_OR_EQUAL_TO(@"8.0")) {
        NSString * fileName = @"native-bundle-main.js";
        if ([WXSDKManager sharedInstance].multiContext) {
            fileName = @"weex-main-jsfm.js";
        }
        [_jsContext evaluateScript:frameworkScript withSourceURL:[NSURL URLWithString:fileName]];
    }else{
        [_jsContext evaluateScript:frameworkScript];
    }
}
/*
 JSContext：Aninstance of JSContext represents a JavaScript execution environment.（一个 Context 就是一个 JavaScript 代码执行的环境，也叫作用域。）
 
 JSValue：Conversionbetween Objective-C and JavaScript types.（JS是弱类型的，ObjectiveC是强类型的，JSValue被引入处理这种类型差异，在Objective-C 对象和 JavaScript 对象之间起转换作用）
 JSContext：给JavaScript提供运行的上下文环境,通过-evaluateScript:方法就可以执行一JS代码
 JSValue：JavaScript和Objective-C数据和方法的桥梁,封装了JS与ObjC中的对应的类型，以及调用JS的API等，提供了多种方法可以方便的将JavaScript数据类型转换成OC或者转换过去。
 JSManagedValue：管理数据和方法的类
 JSVirtualMachine：处理线程相关，使用较少
 JSExport：这是一个协议，如果采用协议的方法交互，自己定义的协议必须遵守此协议
 
 链接：https://www.jianshu.com/p/fad8c7844d3e
 链接：https://www.jianshu.com/p/1ecd7416b2fd
 Block可以传入JSContext作方法，但是JSValue没有toBlock方法来把JavaScript方法变成Block在Objetive-C中使用。毕竟Block的参数个数和类型已经返回类型都是固定的。虽然不能把方法提取出来，但是JSValue提供了- (JSValue *)callWithArguments:(NSArray *)arguments;
 方法可以反过来将参数传进去来调用方法。
 JSContext *context = [[JSContext alloc] init];
 [context evaluateScript:@"function add(a, b) { return a + b; }"];
 JSValue *add = context[@"add"];
 NSLog(@"Func: %@", add);
 JSValue *sum = [add callWithArguments:@[@(7), @(21)]];
 NSLog(@"Sum: %d",[sum toInt32]);
 // OutPut:
 // Func: function add(a, b) { return a + b; }
 // Sum: 28
 JSValue
 还提供- (JSValue *)invokeMethod:(NSString *)method withArguments:(NSArray *)arguments;
 让我们可以直接简单地调用对象上的方法。只是如果定义的方法是全局函数，那么很显然应该在JSContext的globalObject对象上调用该方法；如果是某JavaScript对象上的方法，就应该用相应的JSValue
 */
//由于这些注册的方法的定义是全局函数，那么很显然应该在JSContext的globalObject对象上调用该方法
#warning 有点不明白这个
- (JSValue *)callJSMethod:(NSString *)method args:(NSArray *)args
{
    WXLogDebug(@"Calling JS... method:%@, args:%@", method, args);
    return [[_jsContext globalObject] invokeMethod:method withArguments:args];
}
//js端是直接调用方法 WXBridgeProtocol
- (void)registerCallNative:(WXJSCallNative)callNative
{
    JSValue* (^callNativeBlock)(JSValue *, JSValue *, JSValue *) = ^JSValue*(JSValue *instance, JSValue *tasks, JSValue *callback){
        NSString *instanceId = [instance toString];
        NSArray *tasksArray = [tasks toArray];
        NSString *callbackId = [callback toString];
        WXLogDebug(@"Calling native... instance:%@, tasks:%@, callback:%@", instanceId, tasksArray, callbackId);
        return [JSValue valueWithInt32:(int32_t)callNative(instanceId, tasksArray, callbackId) inContext:[JSContext currentContext]];
    };
    
    _jsContext[@"callNative"] = callNativeBlock;
}

- (void)executeJavascript:(NSString *)script
{
    WXAssertParam(script);
    [_jsContext evaluateScript:script];
}

- (JSValue*)executeJavascript:(NSString *)script withSourceURL:(NSURL*)sourceURL
{
    WXAssertParam(script);
    if (sourceURL) {
        return [_jsContext evaluateScript:script withSourceURL:sourceURL];
    } else {
        return [_jsContext evaluateScript:script];
    }
}

- (void)registerCallAddElement:(WXJSCallAddElement)callAddElement
{
    id callAddElementBlock = ^(JSValue *instanceId, JSValue *ref, JSValue *element, JSValue *index, JSValue *ifCallback) {
        
        NSString *instanceIdString = [instanceId toString];
        NSDictionary *componentData = [element toDictionary];
        NSString *parentRef = [ref toString];
        NSInteger insertIndex = [[index toNumber] integerValue];
        [WXTracingManager startTracingWithInstanceId:instanceIdString ref:componentData[@"ref"] className:nil name:WXTJSCall phase:WXTracingBegin functionName:@"addElement" options:@{@"threadName":WXTJSBridgeThread,@"componentData":componentData}];
         WXLogDebug(@"callAddElement...%@, %@, %@, %ld", instanceIdString, parentRef, componentData, (long)insertIndex);
        
        return [JSValue valueWithInt32:(int32_t)callAddElement(instanceIdString, parentRef, componentData, insertIndex) inContext:[JSContext currentContext]];
    };

    _jsContext[@"callAddElement"] = callAddElementBlock;
}

- (void)registerCallCreateBody:(WXJSCallCreateBody)callCreateBody
{
    id WXJSCallCreateBodyBlock = ^(JSValue *instanceId, JSValue *body,JSValue *ifCallback) {
        
        NSString *instanceIdString = [instanceId toString];
        NSDictionary *bodyData = [body toDictionary];
        
        WXLogDebug(@"callCreateBody...%@, %@,", instanceIdString, bodyData);
        [WXTracingManager startTracingWithInstanceId:instanceIdString ref:bodyData[@"ref"] className:nil name:WXTJSCall phase:WXTracingBegin functionName:@"createBody" options:@{@"threadName":WXTJSBridgeThread}];
        return [JSValue valueWithInt32:(int32_t)callCreateBody(instanceIdString, bodyData) inContext:[JSContext currentContext]];
    };
    
    _jsContext[@"callCreateBody"] = WXJSCallCreateBodyBlock;
}

- (void)registerCallRemoveElement:(WXJSCallRemoveElement)callRemoveElement
{
    id WXJSCallCreateBodyBlock = ^(JSValue *instanceId, JSValue *ref,JSValue *ifCallback) {
        
        NSString *instanceIdString = [instanceId toString];
        NSString *refString = [ref toString];
        
        WXLogDebug(@"callRemoveElement...%@, %@,", instanceIdString, refString);
        [WXTracingManager startTracingWithInstanceId:instanceIdString ref:nil className:nil name:WXTJSCall phase:WXTracingBegin functionName:@"removeElement" options:nil];
        return [JSValue valueWithInt32:(int32_t)callRemoveElement(instanceIdString, refString) inContext:[JSContext currentContext]];
    };
    
    _jsContext[@"callRemoveElement"] = WXJSCallCreateBodyBlock;
}

- (void)registerCallMoveElement:(WXJSCallMoveElement)callMoveElement
{
    id WXJSCallMoveElementBlock = ^(JSValue *instanceId, JSValue *ref,JSValue *parentRef,JSValue *index, JSValue *ifCallback) {
        
        NSString *instanceIdString = [instanceId toString];
        NSString *refString = [ref toString];
        NSString *parentRefString = [parentRef toString];
        NSInteger moveIndex = [[index toNumber] integerValue];
        
        WXLogDebug(@"callAddElement...%@, %@,", instanceIdString, refString);
        [WXTracingManager startTracingWithInstanceId:instanceIdString ref:refString className:nil name:WXTJSCall phase:WXTracingBegin functionName:@"moveElement" options:nil];
        return [JSValue valueWithInt32:(int32_t)callMoveElement(instanceIdString, refString,parentRefString,moveIndex) inContext:[JSContext currentContext]];
    };
    
    _jsContext[@"callMoveElement"] = WXJSCallMoveElementBlock;
}

- (void)registerCallUpdateAttrs:(WXJSCallUpdateAttrs)callUpdateAttrs
{
    id WXJSCallUpdateAttrsBlock = ^(JSValue *instanceId, JSValue *ref,JSValue *attrs, JSValue *ifCallback) {
        
        NSString *instanceIdString = [instanceId toString];
        NSString *refString = [ref toString];
        NSDictionary *attrsData = [attrs toDictionary];
        
        WXLogDebug(@"callUpdateAttrs...%@, %@, %@", instanceIdString, refString,attrsData);
        [WXTracingManager startTracingWithInstanceId:instanceIdString ref:refString className:nil name:WXTJSCall phase:WXTracingBegin functionName:@"updateAttrs" options:@{@"threadName":WXTJSBridgeThread}];
        return [JSValue valueWithInt32:(int32_t)callUpdateAttrs(instanceIdString, refString,attrsData) inContext:[JSContext currentContext]];
    };
    
    _jsContext[@"callUpdateAttrs"] = WXJSCallUpdateAttrsBlock;
}

- (void)registerCallUpdateStyle:(WXJSCallUpdateStyle)callUpdateStyle
{
    id WXJSCallUpdateStyleBlock = ^(JSValue *instanceId, JSValue *ref,JSValue *styles, JSValue *ifCallback) {
        
        NSString *instanceIdString = [instanceId toString];
        NSString *refString = [ref toString];
        NSDictionary *stylessData = [styles toDictionary];
        
        WXLogDebug(@"callUpdateStyle...%@, %@, %@", instanceIdString, refString,stylessData);
        [WXTracingManager startTracingWithInstanceId:instanceIdString ref:refString className:nil name:WXTJSCall phase:WXTracingBegin functionName:@"updateStyle" options:@{@"threadName":WXTJSBridgeThread}];
        return [JSValue valueWithInt32:(int32_t)callUpdateStyle(instanceIdString, refString,stylessData) inContext:[JSContext currentContext]];
    };
    
    _jsContext[@"callUpdateStyle"] = WXJSCallUpdateStyleBlock;
}

- (void)registerCallAddEvent:(WXJSCallAddEvent)callAddEvent
{
    id WXJSCallAddEventBlock = ^(JSValue *instanceId, JSValue *ref,JSValue *event, JSValue *ifCallback) {
        
        NSString *instanceIdString = [instanceId toString];
        NSString *refString = [ref toString];
        NSString *eventString = [event toString];
        
        WXLogDebug(@"callAddEvent...%@, %@, %@", instanceIdString, refString,eventString);
        [WXTracingManager startTracingWithInstanceId:instanceIdString ref:refString className:nil name:WXTJSCall phase:WXTracingBegin functionName:@"addEvent" options:nil];
        return [JSValue valueWithInt32:(int32_t)callAddEvent(instanceIdString, refString,eventString) inContext:[JSContext currentContext]];
    };
    
    _jsContext[@"callAddEvent"] = WXJSCallAddEventBlock;
}

- (void)registerCallRemoveEvent:(WXJSCallRemoveEvent)callRemoveEvent
{
    id WXJSCallRemoveEventBlock = ^(JSValue *instanceId, JSValue *ref,JSValue *event, JSValue *ifCallback) {
        
        NSString *instanceIdString = [instanceId toString];
        NSString *refString = [ref toString];
        NSString *eventString = [event toString];
        
        WXLogDebug(@"callRemoveEvent...%@, %@, %@", instanceIdString, refString,eventString);
        [WXTracingManager startTracingWithInstanceId:instanceIdString ref:refString className:nil name:WXTJSCall phase:WXTracingBegin functionName:@"removeEvent" options:nil];
        return [JSValue valueWithInt32:(int32_t)callRemoveEvent(instanceIdString, refString,eventString) inContext:[JSContext currentContext]];
    };
    
    _jsContext[@"callRemoveEvent"] = WXJSCallRemoveEventBlock;
}
    
- (void)registerCallCreateFinish:(WXJSCallCreateFinish)callCreateFinish
{
    id WXJSCallCreateFinishBlock = ^(JSValue *instanceId, JSValue *ifCallback) {
            
        NSString *instanceIdString = [instanceId toString];
        
        WXLogDebug(@"callRCreateFinish...%@", instanceIdString);
        [WXTracingManager startTracingWithInstanceId:instanceIdString ref:nil className:nil name:WXTJSCall phase:WXTracingBegin functionName:@"createFinish" options:@{@"threadName":WXTJSBridgeThread}];
        return [JSValue valueWithInt32:(int32_t)callCreateFinish(instanceIdString) inContext:[JSContext currentContext]];
    };
        
    _jsContext[@"callCreateFinish"] = WXJSCallCreateFinishBlock;
}

- (void)registerCallNativeModule:(WXJSCallNativeModule)callNativeModuleBlock
{
    _jsContext[@"callNativeModule"] = ^JSValue *(JSValue *instanceId, JSValue *moduleName, JSValue *methodName, JSValue *args, JSValue *options) {
        NSString *instanceIdString = [instanceId toString];
        NSString *moduleNameString = [moduleName toString];
        NSString *methodNameString = [methodName toString];
        NSArray *argsArray = [args toArray];
        NSDictionary *optionsDic = [options toDictionary];
        
        WXLogDebug(@"callNativeModule...%@,%@,%@,%@", instanceIdString, moduleNameString, methodNameString, argsArray);
        
        NSInvocation *invocation = callNativeModuleBlock(instanceIdString, moduleNameString, methodNameString, argsArray, optionsDic);
        JSValue *returnValue = [JSValue wx_valueWithReturnValueFromInvocation:invocation inContext:[JSContext currentContext]];
        [WXTracingManager startTracingWithInstanceId:instanceIdString ref:nil className:nil name:moduleNameString phase:WXTracingInstant functionName:methodNameString options:nil];
        return returnValue;
    };
}

- (void)registerCallNativeComponent:(WXJSCallNativeComponent)callNativeComponentBlock
{
    _jsContext[@"callNativeComponent"] = ^void(JSValue *instanceId, JSValue *componentName, JSValue *methodName, JSValue *args, JSValue *options) {
        NSString *instanceIdString = [instanceId toString];
        NSString *componentNameString = [componentName toString];
        NSString *methodNameString = [methodName toString];
        NSArray *argsArray = [args toArray];
        NSDictionary *optionsDic = [options toDictionary];
        
        WXLogDebug(@"callNativeComponent...%@,%@,%@,%@", instanceIdString, componentNameString, methodNameString, argsArray);
        
        callNativeComponentBlock(instanceIdString, componentNameString, methodNameString, argsArray, optionsDic);
    };
}

- (JSValue*)exception
{
    return _jsContext.exception;
}

- (void)resetEnvironment
{
    NSDictionary *data = [WXUtility getEnvironment];
    _jsContext[@"WXEnvironment"] = data;
}

//typedef void (*WXJSCGarbageCollect)(JSContextRef);

- (void)garbageCollect
{
    // for dev and debug only!!
//    char str[80];
//    strcpy(str, "JSSynchron");
//    strcat(str, "ousGarbageColl");
//    strcat(str, "ectForDebugging");
//    WXJSCGarbageCollect garbageCollect = dlsym(RTLD_DEFAULT, str);
//    
//    if (garbageCollect != NULL) {
//        garbageCollect(_jsContext.JSGlobalContextRef);
//    }
//    JSGarbageCollect(_jsContext.JSGlobalContextRef);
}

#pragma mark - Public
-(void)removeTimers:(NSString *)instance
{
    // remove timers
    if([_callbacks objectForKey:instance]){
        NSMutableArray *arr = [_callbacks objectForKey:instance];
        if(arr && [arr count]>0){
            for (NSString *callback in arr) {
                if([_timers containsObject:callback]){
                    [_timers removeObject:callback];
                }
            }
        }
    }
    // remove intervaltimers
    if(_intervaltimers && [_intervaltimers objectForKey:instance]){
        [_intervaltimers removeObjectForKey:instance];
    }
}

#pragma mark - Private
-(void)addInstance:(NSString *)instance callback:(NSString *)callback
{
    if(instance.length > 0){
        if([_callbacks objectForKey:instance]){
            NSMutableArray *arr = [_callbacks objectForKey:instance];
            if (callback.length>0 && ![arr containsObject:callback]) {
                [arr addObject:callback];
                [_callbacks setObject:arr forKey:instance];
            }
        }else {
            NSMutableArray *arr = [NSMutableArray new];
            if (callback.length>0 && ![arr containsObject:callback]) {
                [arr addObject:callback];
                [_callbacks setObject:arr forKey:instance];
            }
        }
    }
}

- (void)triggerTimeout:(void(^)(void))block
{
    block();
}

- (void)callBack:(NSDictionary *)dic
{
    if([dic objectForKey:@"ret"] && [_timers containsObject:[dic objectForKey:@"ret"]]) {
        [[WXSDKManager bridgeMgr] callBack:[dic objectForKey:@"appId"] funcId:[dic objectForKey:@"ret"]  params:[dic objectForKey:@"arg"] keepAlive:NO];
    }

}


- (void)callBackInterval:(NSDictionary *)dic
{
    if(dic[@"function"] && [dic objectForKey:@"appId"] && [_intervaltimers objectForKey:[dic objectForKey:@"appId"]]){
        NSMutableArray *timers = [_intervaltimers objectForKey:[dic objectForKey:@"appId"]];
        void(^block)(void) = ((void(^)(void))dic[@"function"]);
        if(block && [timers containsObject:[dic objectForKey:@"timerId"]]){
            block();
            [self executeInterval:[dic objectForKey:@"appId"] function:block arg:[dic objectForKey:@"arg"] timerId:[[dic objectForKey:@"timerId"] longLongValue]];
        }
    }
}

- (void)triggerTimeout:(NSString *)appId ret:(NSString *)ret arg:(NSString *)arg
{
    double interval = [arg doubleValue]/1000.0f;
    if(WXFloatEqual(interval,0)) {
        return;
    }
    if(![_timers containsObject:ret]){
        [_timers addObject:ret];
        [self addInstance:appId callback:ret];
    }
    
    NSMutableDictionary *timeoutInfo = [NSMutableDictionary new];
    [timeoutInfo setObject:appId forKey:@"appId"];
    [timeoutInfo setObject:ret forKey:@"ret"];
    [timeoutInfo setObject:arg forKey:@"arg"];
    [self performSelector:@selector(callBack:) withObject:timeoutInfo afterDelay:interval inModes:@[NSRunLoopCommonModes]];
}

- (long long)triggerInterval:(NSString *)appId function:(void(^)(void))block arg:(NSString *)arg
{
    double interval = [arg doubleValue]/1000.0f;
    _intervalTimerId = _intervalTimerId + 1; // timerId must auto-increment.
    long long timerId = _intervalTimerId;
    if(WXFloatEqual(interval,0)) {
        return timerId;
    }
    if([_intervaltimers objectForKey:appId]){
        NSMutableArray *timers = [[_intervaltimers objectForKey:appId] mutableCopy];
        [timers addObject:@(timerId)];
        [_intervaltimers setObject:timers forKey:appId];
    }else {
        NSMutableArray *timers = [NSMutableArray new];
        [timers addObject:@(timerId)];
        [_intervaltimers setObject:timers forKey:appId];
    }
    [self executeInterval:appId function:block arg:arg timerId:timerId];
    return timerId;
}

-(void)executeInterval:(NSString *)appId function:(void(^)(void))block arg:(NSString *)arg timerId:(long long)timerId
{
    double interval = [arg doubleValue]/1000.0f;
    NSMutableDictionary *intervalInfo = [NSMutableDictionary new];
    [intervalInfo setObject:appId forKey:@"appId"];
    [intervalInfo setObject:arg forKey:@"arg"];
    [intervalInfo setObject:@(timerId) forKey:@"timerId"];
    [intervalInfo setObject:[block copy] forKey:@"function"];
    [self performSelector:@selector(callBackInterval:) withObject:intervalInfo afterDelay:interval inModes:@[NSRunLoopCommonModes]];
}

- (void)triggerClearInterval:(NSString *)instanceId ret:(long long)timerId
{
    if(_intervaltimers && [_intervaltimers objectForKey:instanceId]){
        NSMutableArray *timers = [_intervaltimers objectForKey:instanceId];
        if(timers && [timers containsObject:@(timerId)]){
            [timers removeObject:@(timerId)];
        }
    }
}

- (void)triggerClearTimeout:(NSString *)ret
{
    if([_timers containsObject:ret]){
        [_timers removeObject:ret];
    }
}

-(id)extendCallNative:(NSDictionary *)dict
{
    if(dict){
        return [WXExtendCallNativeManager sendExtendCallNativeEvent:dict];
    }
    return @(-1);
}

@end
