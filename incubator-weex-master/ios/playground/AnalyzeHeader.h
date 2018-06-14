//
//  AnalyzeHeader.h
//  WeexDemo
//
//  Created by pingan on 2018/6/14.
//  Copyright © 2018年 taobao. All rights reserved.
//

#ifndef AnalyzeHeader_h
#define AnalyzeHeader_h
/*
 viewdemo->
 _instance->
 - (void)renderWithURL:(NSURL *)url options:(NSDictionary *)options data:(id)data->
 - (void)_renderWithRequest:(WXResourceRequest *)request options:(NSDictionary *)options data:(id)data->
 (重点)_mainBundleLoader.onFinished回调->
 - (void)_renderWithMainBundleString:(NSString *)mainBundleString->
 1.生成_rootView
 2.[[WXSDKManager bridgeMgr] createInstance:self.instanceId template:mainBundleString options:dictionary data:_jsData];->
 (WXBridgeContext)
 [weakSelf.bridgeCtx createInstance:instance
 template:temp
 options:options
 data:data];->
 (self callJSMethod:@"createInstanceContext" args:@[instanceIdString, newOptions, data?:@[]] onContext:nil completion:^(JSValue *instanceContextEnvironment))
 - (void)callJSMethod:(NSString *)method args:(NSArray *)args onContext:(id<WXBridgeProtocol>)bridge completion:(void (^)(JSValue * value))complection ->
 (WXSDKInstance)
 [sdkInstance.instanceJavaScriptContext executeJavascript:jsBundleString withSourceURL:[NSURL URLWithString:sdkInstance.pageName]?:sdkInstance.scriptURL]->
 (WXJSCoreBridge)
 - (JSValue*)executeJavascript:(NSString *)script withSourceURL:(NSURL*)sourceURL->
 (sourceURL:file:///Users/pingan/Library/Developer/CoreSimulator/Devices/9251354C-292B-4832-972C-F2D2F3CDC858/data/Containers/Bundle/Application/B7BDC7EC-A3FA-43BE-B47E-ABAB92BBA8A4/WeexDemo.app/bundlejs/landing.weex.js?random=312950999)
 [_jsContext evaluateScript:script withSourceURL:sourceURL]->
 
 - (void)registerCallAddElement:(WXJSCallAddElement)callAddElement->
 (回调里面调用)WXComponentManager
 [manager addComponent:elementData toSupercomponent:parentRef atIndex:index appendingInTree:NO];->
 - (void)_recursivelyAddComponent:(NSDictionary *)componentData toSupercomponent:(WXComponent *)supercomponent atIndex:(NSInteger)index appendingInTree:(BOOL)appendingInTree->
 [self _addUITask:^{->
 (回调里面处理)[supercomponent insertSubview:component atIndex:index];->
 
 [self.view insertSubview:subcomponent.view atIndex:index];
 - (void)insertSubview:(WXComponent *)subcomponent atIndex:(NSInteger)index->
 - (UIView *)view->
 _view = [self loadView];(根据类自动区分类型)
 

 
 */

#endif /* AnalyzeHeader_h */
