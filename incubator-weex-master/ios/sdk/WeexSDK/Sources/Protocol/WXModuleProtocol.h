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

#import <UIKit/UIKit.h>
#import "WXDefine.h"
#import "WXSDKInstance.h"

#define MSG_SUCCESS     @"WX_SUCCESS"
#define MSG_NO_HANDLER  @"WX_NO_HANDLER"
#define MSG_NO_PERMIT   @"WX_NO_PERMISSION"
#define MSG_FAILED      @"WX_FAILED"
#define MSG_PARAM_ERR   @"WX_PARAM_ERR"
#define MSG_EXP         @"WX_EXCEPTION"

@protocol WXModuleProtocol <NSObject>
/*
 在Weex中，iOS Native把事件传递给JS目前只有2种方式，一是Module模块的callback，二是通过Component组件自定义的通知事件。
 两个闭包都可以callback把data传递回给JS，data可以是字符串或者字典。
 
 这两个闭包的区别在于：
 
 WXModuleCallback用于Module组件，为了节约内存，该回调只能回调通知JS一次，之后会被释放，多用于一次结果。
 WXModuleKeepAliveCallback同样是用于Module组件，但是该回调可以设置是否为多次回调类型，如果设置了keepAlive，那么可以进行持续监听变化，多次回调，并返回给 JS。
 在Weex中使用WXModuleCallback回调，很多情况是把状态回调给JS，比如成功或者失败的状态，还有一些出错的信息回调给JS。
 
 作者：一缕殇流化隐半边冰霜
 链接：https://www.jianshu.com/p/419b96aecc39
 來源：简书
 著作权归作者所有。商业转载请联系作者获得授权，非商业转载请注明出处。
 注册回调方法
 WX_EXPORT_METHOD(@selector(push:callback:))
 */
/**
 * @abstract the module callback , result can be string or dictionary.
 * @discussion callback data to js, the id of callback function will be removed to save memory.
 */
typedef void (^WXModuleCallback)(id result);
//DEPRECATED_MSG_ATTRIBUTE("use WXModuleKeepAliveCallback, you can specify keep the callback or not, if keeped, it can be called multi times, or it will be removed after called.")

/**
 * @abstract the module callback , result can be string or dictionary.
 * @discussion callback data to js, you can specify the keepAlive parameter to keep callback function id keepalive or not. If the keepAlive is true, it won't be removed until instance destroyed, so you can call it repetitious.
 */
typedef void (^WXModuleKeepAliveCallback)(id result, BOOL keepAlive);

#define WX_EXPORT_MODULE(module) 

@optional

/**
 *  @abstract returns the execute queue for the module
 *
 *  @return dispatch queue that module's methods will be invoked on
 *
 *  @discussion the implementation is optional. Implement it if you want to execute module actions in the special queue.
 *  Default dispatch queue will be the main queue.
 *
 */
- (dispatch_queue_t)targetExecuteQueue;

/**
 *  @abstract returns the execute thread for the module
 *
 *  @return  thread that module's methods will be invoked on
 *
 *  @discussion the implementation is optional. If you want to execute module actions in the special thread, you can create a new one. 
 *  If `targetExecuteQueue` is implemented,  the queue returned will be respected first.
 *  Default is the main thread.
 *
 */
- (NSThread *)targetExecuteThread;

/**
 *  @abstract the instance bind to this module. It helps you to get many useful properties related to the instance.
 */
@property (nonatomic, weak) WXSDKInstance *weexInstance;

@end
