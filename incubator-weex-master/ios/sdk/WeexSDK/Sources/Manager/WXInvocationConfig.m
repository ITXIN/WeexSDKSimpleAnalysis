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

#import "WXInvocationConfig.h"
#import "WXLog.h"
#import "WXSDKInstance.h"
#import "WXSDKManager.h"
#import "WXSDKInstance_private.h"
#import "WXMonitor.h"
#import "WXSDKError.h"
#import "WXComponentFactory.h"
#import "WXModuleFactory.h"
#import "WXUtility.h"

#import <objc/runtime.h>

@interface WXInvocationConfig()
@end

@implementation WXInvocationConfig

- (instancetype)init
{
    
    if (self = [super init]) {
        _asyncMethods = [NSMutableDictionary new];
        _syncMethods = [NSMutableDictionary new];
    }
    
    return self;
}

- (instancetype)initWithName:(NSString *)name class:(NSString *)clazz
{
    if (self = [self init]) {
        _name = name;
        _clazz = clazz;
    }
    return self;
}

- (void)registerMethods
{
    Class currentClass = NSClassFromString(_clazz);
    
    if (!currentClass) {
        WXLogWarning(@"The module class [%@] doesn't exit！", _clazz);
        return;
    }
#warning 方法列表什么时候添加的？是通过 WX_EXPORT_METHOD
    while (currentClass != [NSObject class]) {
        unsigned int methodCount = 0;
        // 获取类方法列表(+号方法)
        Method *methodList = class_copyMethodList(object_getClass(currentClass), &methodCount);
        for (unsigned int i = 0; i < methodCount; i++) {
            // 获取SEL的字符串名称
            NSString *selStr = [NSString stringWithCString:sel_getName(method_getName(methodList[i])) encoding:NSUTF8StringEncoding];
            BOOL isSyncMethod = NO;
             // 如果是SEL名字带sync，就是同步方法
            if ([selStr hasPrefix:@"wx_export_method_sync_"]) {
                isSyncMethod = YES;
            } else if ([selStr hasPrefix:@"wx_export_method_"]) {// 如果是SEL名字不带sync，就是异步方法
                isSyncMethod = NO;
            } else {  // 如果名字里面不带wx_export_method_前缀的方法，那么都不算是暴露出来的方法，直接continue，进行下一轮的筛选
                continue;
            }
            
            NSString *name = nil, *method = nil;
            SEL selector = NSSelectorFromString(selStr);
            if ([currentClass respondsToSelector:selector]) {
                method = ((NSString* (*)(id, SEL))[currentClass methodForSelector:selector])(currentClass, selector);
            }
            
            if (method.length <= 0) {
                WXLogWarning(@"The module class [%@] doesn't has any method！", _clazz);
                continue;
            }
            // 去掉方法名里面带的：号
            NSRange range = [method rangeOfString:@":"];
            if (range.location != NSNotFound) {
                name = [method substringToIndex:range.location];
            } else {
                name = method;
            }
            
            // 最终字典里面会按照异步方法和同步方法保存到最终的方法字典里
            NSMutableDictionary *methods = isSyncMethod ? _syncMethods : _asyncMethods;
            [methods setObject:method forKey:name];
        }
        
        free(methodList);
        currentClass = class_getSuperclass(currentClass);
    }
    
}

@end
