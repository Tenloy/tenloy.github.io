---
title: WKWebView使用过程中遇到的坑
date: 2022-01-18 17:39:45
urlname: wkwebview-buges.html
tags:
categories:
  - iOS
---

# 一、WKWebView的使用

## 1.1 属性

关于 `extendedLayoutIncludesOpaqueBars` 和 `automaticallyAdjustsScrollViewInsets`

* 这两个属性属于UIViewController
* 默认情况下extendedLayoutIncludesOpaqueBars = false 扩展布局不包含导航栏
* 默认情况下automaticallyAdjustsScrollViewInsets = true 自动计算滚动视图的内容边距
* 但是，当 导航栏 是 不透明时，而tabBar为透明的时候，为了正确显示tableView的全部内容，需要重新设置这两个属性的值，然后设置contentInset(参考代码).

在iOS11 中， UIViewController的 `automaticallyAdjustsScrollViewInsets` 属性已经不再使用，我们需要使用UIScrollView的 `contentInsetAdjustmentBehavior ` 属性来替代它.

UIScrollViewContentInsetAdjustmentBehavior 是一个枚举类型，值有以下几种:

* automatic 和scrollableAxes一样，scrollView会自动计算和适应顶部和底部的内边距并且在scrollView 不可滚动时，也会设置内边距.
* scrollableAxes 自动计算内边距.
* never不计算内边距
* always 根据safeAreaInsets 计算内边距一般我们肯定需要设置为 never，我们自己来控制间距，但是在iOS 12的webView中，就会出现开始所说的问题，需要设置为automatic才能解决

**调整WKWebView布局方式，避免调整webView.scrollView.contentInset。实际上，即便在 UIWebView 上也不建议直接调整webView.scrollView.contentInset的值.**

## 1.2 调整滚动速率

WKWebView 需要通过 scrollView delegate 调整滚动速率：

```objectivec
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
  scrollView.decelerationRate = UIScrollViewDecelerationRateNormal;
}
```

## 1.3 视频自动播放

WKWebView 需要通过WKWebViewConfiguration.mediaPlaybackRequiresUserAction设置是否允许自动播放，但一定要在 WKWebView 初始化之前设置，在 WKWebView 初始化之后设置无效。

## 1.4 goBack API问题

WKWebView 上调用 -[WKWebView goBack]， 回退到上一个页面后不会触发window.onload()函数、不会执行JS。

## 1.5 WKWebview+NSURLProtocol实现网页缓存

### 1.5.1 前言

出于节省hybrid app的性能，以及加载时间，对app内的一些资源做缓存处理，包括：图片、js文件。
首先，我们需要能拦截到这些请求，实验之后，发现`NSURLProtocol`在`WKWebViwe`中不生效。
本文分一下两个部分：

- 让WKWebView支持NSURLProtocol，摘抄了[这篇博客](https://blog.csdn.net/u011661836/article/details/70241061)大篇幅内容，其中有关于**苹果对私有API的监测以及开发人员的应对措施**
- 对资源做缓存措施

### 1.5.2 让WKWebView支持NSURLProtocol

在UIWebView中，只需要一行代码`[NSURLProtocol registerClass:[customeURLProtocol class]];`，就可以对app内所有的网络请求进行拦截处理。

但是在WKWebView中，除了一开始会调用一下 `+ [NSURLProtocol canInitWithRequest:]` 方法，之后就全拦截不到了。网上查，说是WKWebView 的请求是在单独的进程里，所以不走 NSURLProtocol。

#### 1. registerSchemeForCustomProtocol

从方法名来猜测，它的作用的应该是**注册一个自定义的 scheme**，这样对于 WebKit 进程的所有网络请求，都会先检查是否有匹配的 scheme，有的话再走主进程的 NSURLProtocol 这一套流程。

博客作者猜测这么做可能是为了保证效率 (**NSURLRequest 的 HTTPBody 属性在 WKWebView 中被忽略了应该也出于这个原因!!! --- 这是个大坑 不能发POST请求了！**)，毕竟 IPC 代价挺高的。详细可以看： `WebKit::CustomProtocolManager` 和 `WebKit::WebProcessPool` 等相关源码

解决方案：

```objectivec
Class cls = NSClassFromString(@"WKBrowsingContextController");
SEL sel = NSSelectorFromString(@"registerSchemeForCustomProtocol:");
if ([(id)cls respondsToSelector:sel]) {
// 把 http 和 https 请求交给 NSURLProtocol 处理
[(id)cls performSelector:sel withObject:@"http"];
[(id)cls performSelector:sel withObject:@"https"];
```

此时，`[NSURLProtocol registerClass:[customeURLProtocol class]]`就可以生效了

#### 2. 优化 - 私有API检测

##### 关于私有 API

按照 @sunnyxx 的[总结](http://blog.sunnyxx.com/2015/06/07/fullscreen-pop-gesture/)，Apple 检查私有 API 的使用，大概会采取下面几种手段：

- 是否 link 了私有 framework 或者公开 framework 中的私有符号，这可以防止开发者把私有 header 都 dump 出来供程序直接调用。
- 同上，使用@selector(_private_sel)加上-performSelector:的方式直接调用私有 API。
- 扫描所有符号，查看是否有继承自私有类，重载私有方法，方法名是否有重合。
- 扫描所有string，看字符串常量段是否出现和私有 API 对应的。

```objectivec
Class cls = NSClassFromString(@"WKBrowsingContextController");
SEL sel = NSSelectorFromString(@"registerSchemeForCustomProtocol:");
```

上面两行代码非常之符合第四条。

解决方案：

查询 [WKWebView.h](https://github.com/JaviSoto/iOS10-Runtime-Headers/blob/master/Frameworks/WebKit.framework/WKWebView.h) 可以看到，有个方法 `- browsingContextController` 的方法名跟 `WKBrowsingContextController` 长得很像，通过 KVC 取出来（没错，KVC 不但可以取 property 取 ivar，还可以取无入参 selector 的返回值）发现它就是 `WKBrowsingContextController` 的一个实例，这样一来这个私有类就可以通过 KVC 的方式来得到了：

```dart
Class cls = [[[WKWebView new] valueForKey:@"browsingContextController"] class];
```

`valueForKey` 比直接使用 `NSClassFromString`安全了许多。

其他解决方案：这些字符串也可以不明着写出来，只要运行时算出来就行，比如用 base64 编码啊，图片资源里藏一段啊，甚至通过服务器下发……

##### 使用私有 API 的另一风险是兼容性问题

比如上面的 `browsingContextController` 就只能在 iOS 8.4 以后才能用，反注册 scheme 的方法 `unregisterSchemeForCustomProtocol:`也是在 iOS 8.4 以后才被添加进来的。

要支持 iOS 8.0 ~ 8.3 机型的话，只能通过动态生成字符串的方式拿到 `WKBrowsingContextControlle`，而且还**不能反注册**，不过这些问题都不大。至于向后兼容，这个也不用太担心，因为 iOS 发布新版本之前都会有**开发者预览版**的，那个时候可以提前关注测一下。对于以上的例子来说，如果将来哪个 iOS 版本移除了这个 API，那很可能是因为官方提供了完整的解决方案，到那时候自然也不需要以上的方法了。

### 1.5.3 对资源做缓存措施

#### 1. 图片资源

通过`response.MIMEType`判断如果是: `image/gif` `image/jpeg` `image/jpg` `image/png`利用SDWebImage提供的缓存api来存储数据：

```objectivec
- (void)storeImage:(nullable UIImage *)image
     imageData:(nullable NSData *)imageData
        forKey:(nullable NSString *)key
        toDisk:(BOOL)toDisk
    completion:(nullable SDWebImageNoParamsBlock)completionBlock;    
```

#### 2. 文件

文件之类的我们是使用本地存储来做缓存

### 1.5.4 问题及处理

- 这么做有隐患，自定义`NSURLProtocol` 会影响`WKWebView`中POST请求，所以使用起来还得根据场景来看
  - 控制自定义的协议的开关时机
  - 如果实在冲突可以再创建一个WKWebView、UIWebView的控制器，根据场景分开使用
- 有一阵，页面上有一些图片资源无法正常加载，下拉刷新无效，怀疑是缓存了错误资源，两个方面：1. CDN资源有问题 2. 缓存策略有问题。
- 不会拦截原生AFN请求(也不算问题，一般也没必要)
  - 如果监控网络是通过注册NSURLProtocol来进行网络监控的，而且是用的AFN3.0，那么是拦截不到的，通过 `sessionWithConfiguration:delegate:delegateQueue:`得到的session，他的configuration中已经有一个NSURLProtocol，所以不会走自定义的protocol（通过share得到的session没这个问题)

解决方案：

- 我们将NSURLSessionConfiguration的属性`protocolClasses的get方法`hook掉，通过返回自定义的protocol,这样，我们就能够监控到通过 `sessionWithConfiguration:delegate:delegateQueue:`得到的session的网络请求
- 在AFHTTPSessionManager中注册

```objc
NSMutableArray *protocols = [NSMutableArray arrayWithArray:manager.session.configuration.protocolClasses];

[protocols insertObject:[customeURLProtocol class] atIndex:0];
manager.session.configuration.protocolClasses = [protocols copy];

//manager是你发送请求时的AFHTTPSessionManager类，注意不能用[AFHTTPSessionManager manager]代替[AFHTTPSessionManager manager]其实不是单例，每次调用的时候都会init出一个新的manager，因此只能在每次初始化好manager之后都注册一次NSURLProtocol
```

## 1.6 Cookie的传递

iOS下的cookie机制：

- iOS平台下每一个APP都有自己的Cookie，APP之间不共享Cookie，一个Cookie 对应一个NSHTTPCookie实体，并通过NSHTTPCookieStrorage进行管理。那些需要持久化的Cookie是存放在`~/Library/Cookies/Cookies.binarycookies` 文件中的二进制格式。

- cookie是iOS系统默认持久化存储的，一般我们使用到cookie的地方，都要注意cookie的更新，删除。

### 1.6.1 UIWebview 相关API

```objc
@interface NSHTTPCookieStorage : NSObject

- (nullable NSArray<NSHTTPCookie *> *)cookiesForURL:(NSURL *)URL;
- (void)deleteCookie:(NSHTTPCookie *)cookie;

@end

// 这个地方，明明缓存策略是：忽略本地和远程的缓存，重新加载。但是好像还是会取本地存储的，发送上去，也不知道为什么？只能手动清理
[webView loadRequest:[NSURLRequest requestWithURL: url cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData timeoutInterval:30]];
```

Cookie的生成途径有两种：

- 一种是访问网页，网页返回的是HTTP Header 中有 Set-Cookie指令进行Cookie 的设置，这里Cookie 的本地处理其实是由WebKit 进行的  

  ```objc
  [[NSHTTPCookieStorage sharedHTTPCookieStorage] setCookie:cookie];
  ```

- 还有一种途径就是我们客户端通过手动设置的Cookie

  ```objc
  [request setValue:[NSString stringWithFormat:@"%@=%@",[cookie name],[cookie value]] forHTTPHeaderField:@"Cookie"];
  ```

以上两种说的是UIWebView的设置方法

### 1.6.2 WKWebView相关API

WKWebView的取、设置，理论详见[WKWebView 那些坑 — Cookie 问题](https://mp.weixin.qq.com/s/rhYKLIbXOsUJC_n6dt9UfA?)

业界普遍认为 WKWebView 拥有自己的私有存储，不会将 Cookie 存入到标准的 Cookie 容器 NSHTTPCookieStorage 中。会忽略任何的默认网络存储器(`NSURLCache`, `NSHTTPCookieStorage`, `NSCredentialStorage`) 和一些标准的自定义网络请求类(`NSURLProtocol`,等等.)，导致`NSURLCache`和`NSHTTPCookieStroage`无法操作(WKWebView)WebCore进程的缓存和Cookie

实践发现 WKWebView 实例其实也会将 Cookie 存储于 NSHTTPCookieStorage 中，但存储时机有延迟，在iOS 8上，当页面跳转的时候，当前页面的 Cookie 会写入 NSHTTPCookieStorage 中，而在 iOS 10 上，JS 执行 document.cookie 或服务器 set-cookie 注入的 Cookie 会很快同步到 NSHTTPCookieStorage 中，FireFox 工程师曾建议通过 reset WKProcessPool 来触发 Cookie 同步到 NSHTTPCookieStorage 中，实践发现不起作用，并可能会引发当前页面 session cookie 丢失等问题。

WKWebView Cookie 问题在于**WKWebView 发起的请求不会自动带上**存储于 NSHTTPCookieStorage 容器中的 Cookie。而**UIWebView是自动注入cookie**。

与Cookie相同的情况就是WKWebView的缓存、凭据等。WKWebView都拥有自己的私有存储，因此和标准cocoa网络类兼容的不是那么好。

#### 1. webView设置cookie

  + JS注入的Cookie，比如PHP代码在Cookie容器中取是取不到的， javascript document.cookie能读取到，浏览器中也能看到。
  + NSMutableURLRequest 注入的PHP等动态语言直接能从$_COOKIE对象中获取到，但是js读取不到，浏览器也看不到。

解决方案：

```objectivec
1.在初始化时，通过js注入添加cookies
// WKUserContentController对象为JavaScript提供了一种方式，可以将消息发送到web视图，并将用户脚本注入到web视图中。
NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
//设置cookie，传值给服务端
NSString *cookie1 = [NSString stringWithFormat:@"document.cookie='goola_app_latitude=%lf'",userLocation.location.coordinate.latitude];
NSString *cookie2 = [NSString stringWithFormat:@"document.cookie='goola_app_longitude=%lf'",userLocation.location.coordinate.longitude];
        
WKUserContentController *userContentController = self.webView.configuration.userContentController;
        
WKUserScript *script1 = [[WKUserScript alloc] initWithSource:cookie1 injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO];
WKUserScript *script2 = [[WKUserScript alloc] initWithSource:cookie2 injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO];
     
[userContentController addUserScript:script1];
[userContentController addUserScript:script2];


2.给发出的request也添加上cookies
NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:20.0f];
[request setValue:@"userId=zhangpeng" forHTTPHeaderField:@"Cookie"];
[_webView loadRequest:request];
```

#### 2. webview取cookie

```objc
//iOS11之前(好像失效了？？解决无果，换UIWebView了)
- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler{
    
    NSHTTPURLResponse *response = (NSHTTPURLResponse *)navigationResponse.response;
    NSArray *cookies =[NSHTTPCookie cookiesWithResponseHeaderFields:[response allHeaderFields] forURL:response.URL];
    //读取wkwebview中的cookie
    for (NSHTTPCookie *cookie in cookies) {
        // 这里就是你需要的cookie
        NSLog(@"%@----%@----%lu----",cookie.name,cookie.value,cookie.version);
    }
    decisionHandler(WKNavigationResponsePolicyAllow);
}

//iOS11之后，存取都发生了变化
//WKHTTPCookieStore的使用 
WKHTTPCookieStore *cookieStore = self.webView.configuration.websiteDataStore.httpCookieStore;
//get cookies
[cookieStore getAllCookies:^(NSArray<NSHTTPCookie *> * _Nonnull cookies) {
      NSLog(@"All cookies %@",cookies);
}];

WKHTTPCookieStore *cookieStore = self.webView.configuration.websiteDataStore.httpCookieStore;
[cookieStore setCookie:cookie completionHandler:nil];
```

# 二、遇到的问题

在以前，一直以为Hybrid App开发是一种略显简单的事，不会使用太多能发挥移动端原生本身优势的复杂API，后来在新公司的工作(半混合式开发)过程中，发现混合式开发也是很多坑... 或者说WKWebView好多坑...

>  以下所说的内容，[参考链接](https://mp.weixin.qq.com/s/rhYKLIbXOsUJC_n6dt9UfA?)上基本上都有，本文的叙述方式主要是结合自己的经历(自己踩过的总结总是那么的深刻...[\捂脸])
>
>  应该在开始混合开发之前就看下这篇文章的，结果真的是等自己踩坑踩了一遍，总结之后，发现这篇文章上都有....[\大哭]
>
>  参考链接2： https://www.jianshu.com/p/86d99192df68

## 1. 加载URL的 encode问题

在数据网络请求或其他情况下，需要把URL中的一些特殊字符转换成UTF-8编码，比如：中文。解决**无法加载**的问题
### 编码

```objectivec
// iOS 9以前
stringByAddingPercentEscapesUsingEncoding: NSUTF8StringEncoding

// ios9后对其方法进行了修改
stringByAddingPercentEncodingWithAllowedCharacters: [NSCharacterSet URLQueryAllowedCharacterSet]
```

### 解码

```objectivec
// iOS 9以前
stringByReplacingPercentEscapesUsingEncoding: NSUTF8StringEncoding
  
// iOS 9以后
stringByRemovingPercentEncoding
```

总结：

- 混合开发中，最好将所有的URL的编解码问题都**交给前端或者后端来做**，毕竟移动端发版不够灵活。
- API编写时，要**保证iOS与Android两端的处理一致**，否则前端同学做处理就太麻烦了。

## 2. loadRequest造成的body数据丢失

在 WKWebView 上通过 loadRequest 发起的 post 请求 body 数据会丢失：

```objectivec
//同样是由于进程间通信性能问题，HTTPBody字段被丢弃[request setHTTPMethod:@"POST"];
[request setHTTPBody:[@"bodyData" dataUsingEncoding:NSUTF8StringEncoding]];
[wkwebview loadRequest: request];
```

目前也已经有成熟的解决方案了，见[KKJSBridge库](https://github.com/karosLi/KKJSBridge#ajax-hook-%E6%96%B9%E6%A1%88%E5%AF%B9%E6%AF%94)。原理上都是hook ajax，不过细节上分两种：

这里只对比方案间相互比较的优缺点，共同的优点，就不赘述了。如果对私有 API 不敏感的，我是比较推荐使用方案一的。

### 方案一：Ajax Hook 部分 API + NSURLProtocol

这个方案对应的是这里的 `KKJSBridge/AjaxProtocolHook`。

原理介绍：此种方案，是只需要 hook ajax 中的 open/send 方法。

1. 在 hook 的 send 方法里，先把要发送的 body 通过 JSBridge 发送到 Native 侧去缓存起来。
   - *为每一个post请求设置一个id，对应其缓存起来的body数据？*
   - *如果不想缓存，那先把post转get、或者body参数存header中，缺点都是body有限制。这种适合参数较少时。注意有个坑就是修改header可能会导致发出options请求。—— 来自群友交流*
2. 缓存成功后，再去执行真实的 send 方法，NSURLProtocol 此时会拦截到该请求，然后取出之前缓存的 body 数据，重新拼接请求，就可以发送出去了。
3. 然后通过 NSURLProtocol 把请求结果返回给 WebView 内核。

优点：

- 兼容性会更好，网络请求都是走 webview 原生的方式。
- hook 的逻辑会更少，会更加稳定。
- 可以更好的支持 ajax 获取二进制的数据。例如 H5 小游戏场景（白鹭引擎是通过异步获取图片资源）。

缺点：

- 需要使用到私有 API browsingContextController 去注册 http/https。（其实现在大部分的离线包方案也是使用了这个私有 API 了）

### 方案二：Ajax Hook 全部 API

这个方案对应的是这里的 `KKJSBridge/AjaxHook`。

原理介绍：此种方案，是使用 hook 的 XMLHttpRequest 对象来代理真实的 XMLHttpRequest 去发送请求，相当于是需要 hook ajax 中的所有方法。

- 在 hook 的 open 方法里，调用 JSBridge 让 Native 去创建一个 NSMutableRequest 对象。
- 在 hook 的 send 方法里，把要发送的 body 通过 JSBridge 发送到 Native 侧，并把 body 设置给刚才创建的 NSMutableRequest 对象。
- 在 Native 侧完成请求后，通过 JS 执行函数，把请求结果通知给 JS 侧，JS 侧找到 hook 的 XMLHttpRequest 对象，最后调用 onreadystatechange 函数，让 H5 知道有请求结果了。

优点：

- 没有使用私有 API。

缺点：

- 需要 hook XMLHttpRequest 的所有方法。
- 请求结果是通过 JSBrdige 来进行传输的，性能上肯定没有原生的性能好。
- 不能支持 ajax 获取二进制的数据。要想支持的话，还需要额外的序列化工作。

## 3. WKUserContentController造成内存泄漏

> self -> webView -> WKWebViewConfiguration -> WKUserContentController -> self (addScriptMessageHandler)

以下的方法，并不能解决问题

```objectivec
__weak typeof(self) copy_self = self;
addScriptMessageHandler: copy_self
```

解决方案： 单独创建一个类实现`WKScriptMessageHandler`协议，然后在该类中再创建一个协议，由self来实现协议。

```objectivec
self -> webView -> WKWebViewConfiguration -> WKUserContentController -> weak delegate obj --delegate--> self
```

示例代码：

```objectivec
//1.创建一个新类WeakScriptMessageDelegate
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
@interface WeakScriptMessageDelegate : NSObject
@property (nonatomic, weak) id<WKScriptMessageHandler> scriptDelegate;
- (instancetype)initWithDelegate:(id<WKScriptMessageHandler>)scriptDelegate;
@end

@implementation WeakScriptMessageDelegate

- (instancetype)initWithDelegate:(id<WKScriptMessageHandler>)scriptDelegate {
    self = [super init];
    if (self) {
      _scriptDelegate = scriptDelegate;
    }
    return self;
}

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    [self.scriptDelegate userContentController:userContentController didReceiveScriptMessage:message];
}

@end

// 2.在我们使用WKWebView的控制器中引入我们创建的那个类，将注入js对象的代码改为:
[config.userContentController addScriptMessageHandler:[[WeakScriptMessageDelegate alloc] initWithDelegate:self] name:scriptMessage];

// 3.在delloc方法中通过下面的方式移除注入的js对象
[self.config.userContentController removeScriptMessageHandlerForName:scriptMessage];
```

上面三步就可以解决控制器不能被释放的问题了。

## 4.  WKWebView的白屏问题(拍照引起)

### 原理

WKWebView 自诩拥有更快的加载速度，更低的内存占用，但实际上 WKWebView 是一个多进程组件，Network Loading 以及 UI Rendering 在其它进程中执行。

换WKWebView加载网页后，App 进程内存消耗反而大幅下降，但是仔细观察会发现，Other Process 的内存占用会增加。**在一些用 webGL 渲染的复杂页面，使用 WKWebView 总体的内存占用（App Process Memory + Other Process Memory）不见得比 UIWebView 少很多。**

- 在 UIWebView 上当内存占用太大的时候，App Process 会 crash；
- 在 WKWebView 上当总体的内存占用比较大的时候，WebContent Process 会 crash，从而出现白屏现象

### 解决方案

总结下来，白屏的现象有几种：

- WKWebView的URL为空，出现白屏，这种现象可以通过loadRequest解决。
- WKWebView的URL不空，出现白屏、部分白屏、白屏部分能点击，这种现象无论是reload还是loadRequest都不能刷出网页。（可以尝试3、4）

#### 方案1. ContentProcessDidTerminate

借助 iOS 9以后 `WKNavigtionDelegate` 新增了一个回调函数：

```objectivec
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView API_AVAILABLE(macosx(10.11), ios(9.0));
```

当 WKWebView 总体内存占用过大，页面即将白屏的时候，系统会调用上面的回调函数，我们在该函数里执行`[webView reload]`(这个时候 webView.URL 取值尚不为 nil）解决白屏问题。在一些高内存消耗的页面可能会频繁刷新当前页面，H5侧也要做相应的适配操作。

#### 方案2. 检测 webView.title 是否为空

并不是所有H5页面白屏的时候都会调用上面的回调函数，比如，最近遇到在一个高内存消耗的**意见反馈**H5页面上 present 系统相机，拍照完毕后返回原来页面的时候出现白屏现象（拍照过程消耗了大量内存，导致内存紧张，**WebContent Process 被系统挂起**），但上面的回调函数并没有被调用。

在WKWebView白屏的时候，另一种现象是 webView.titile 会被置空， 因此，可以在 viewWillAppear 的时候检测 `webView.title` 是否为空来 reload 页面。

注意：可能**有的前端页面确实没写title标签**，在前端移动端开发中是可能会有这种场景的，会造成页面反复刷新

综合以上两种方法可以解决绝大多数的白屏问题。

#### 方案3. 检索WKCompositingView控件

> （*未验证，有人说不好使*）

WKWebView的URL不空，出现白屏不能点击、白屏部分能点击、部分白屏能点击等，这种现象无论是reload、loadRequest、清缓存、setNeedsLayout都不能刷出网页，只能回收旧webview（webview = nil 后记得清除代理，移除监听，要不然会crash）创建新的 webview， 然后重新request。

```objectivec
// 判断是否白屏
- (BOOL)isBlankView:(UIView *)view { // YES：blank
    Class wkCompositingView = NSClassFromString(@"WKCompositingView");
    if ([view isKindOfClass:[wkCompositingView class]]) {
        return NO;
    }
    for(UIView * subView in view.subviews) {
        if (![self isBlankView:subView]) {
            return NO;
        }
    }
	return YES;
}
```

#### 方案4. html中加入资源加载的监听

在本地html中加入资源加载的监听，只要发生错误，就调用location.reload();重载当前文档。

```objectivec
//监控资源加载错误(img,script,css,以及jsonp)
window.addEventListener('error', function (e) {
    console.log("===" + e.message + "===");
    location.reload();
}, true);

window.onerror = function (errorMessage, scriptURI, lineNumber, columnNumber, errorObj) {
    console.log("错误信息：", errorMessage);
    console.log("出错文件：", scriptURI);
    console.log("出错行号：", lineNumber);
    console.log("出错列号：", columnNumber);
    console.log("错误详情：", errorObj);
}
```

注：这段代码要放在head内，并且css不能内联。

## 5. NSURLProtocol(做网页缓存)

见[WKWebView中NSURLProtocol的使用以及对H5的缓存](https://www.jianshu.com/p/9989ef064f7d)，这是利用NSURLProtocol做网页缓存以及带来的隐患。

## 6.  WKWebView的截屏问题(做意见反馈)

WKWebView 下通过 `-[CALayer renderInContext:]`实现截屏的方式失效，需要通过以下方式实现截屏功能：

```objectivec
@implementation UIView (ImageSnapshot) 
- (UIImage*)imageSnapshot { 
    UIGraphicsBeginImageContextWithOptions(self.bounds.size,YES,self.contentScaleFactor); 
    [self drawViewHierarchyInRect:self.bounds afterScreenUpdates:YES]; 
    UIImage* newImage = UIGraphicsGetImageFromCurrentImageContext(); 
    UIGraphicsEndImageContext(); 
    return newImage; 
} 
@end
```
然而这种方式依然解决不了 webGL 页面的截屏问题，Safari 以及 Chrome 这两个全量切换到 WKWebView 的浏览器也存在同样的问题：**对webGL 页面的截屏结果不是空白就是纯黑图片**。

## 7. window.alert()引起的crash问题(暂时没遇到)

## 8. WKWebView拦截协议

WKWebView内默认不允许iTunes、weixin等协议跳转。

UIWebView打开ituns.apple.com、跳转到appStore、拨打电话、唤起邮箱等一系列操作，UIWebView自己处理不了会自动交给UIApplication 来处理。

WKWebView上述事件WKWebView 不会自动交给UIApplication 来处理，除此之外，js端通过window.open() 打开新的网页的动作也被禁掉了。

## 9. User-Agent修改

- 在UIWebView初始化之前，全局设置User-Agent才会生效
- 在shouldStartLoadWithRequest可以给某个request设置UA，但是需要重新[webView loadUrl]，注意判断条件，不要死循环
- **不要擅自修改webView的User-Agent，务必要跟前端反复确认，是否有用UA来做一些设备区分，进而做一些系统、机型适配问题。**

## 10. didFinish不调用

WKWebView didFinishNavigation明明看起来页面加载完全，却不调用(**一般只发生在第一次进入该页面**)。经过自定义NSURLProtocol，拦截所有的H5加载资源，并在didCompleteWithError中打印资源的加载情况，发现有图片资源，域名有问题。

```objectivec
Error Domain=NSURLErrorDomain Code=-1003 "未能找到使用指定主机名的服务器。 
```

原因：DNS解析失败导致系统认定H5一直没加载完成！第二次再进入，系统缓存了DNS解析的映射记录，所以很快就认定资源错误，调用了didFinish方法。

## 11. UI细节问题

### 11.1 WKWebView中 h5绝对布局不生效

```objectivec
// ios 11之后
_baseWebView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
```
然后：前端需要在meta标签中增加 **iPhoneX**的适配**---**适配方案**viewport-fit**：**cover**

### 11.2. iOS 12中WKWebView中表单 键盘

iOS 12中WKWebView中表单键盘弹起自动上移，导致的兼容问题。

WKWebView会自动监听键盘弹出，并做上下移动处理(效果如同IQKeyboardManage这些库)，但是在iOS12中会有一些问题，键盘收起后，控件不恢复原状，或者部分控件消失等不兼容问题

解决方案：

```objectivec
if(kSystemVersion < 12.0) {
    if (@available(iOS 11.0, *)) {
        _webview.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    } 
}
if (@available(iOS 12.0, *)) {
     _webview.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;
}
```

### 11.3 WKWebview会下移20 

解决方案：
```objectivec
//iOS11前
VC.automaticallyAdjustsScrollViewInsets = NO;  
//iOS11及以后
_webview.scrollView.contentInsetAdjustmentBehavior;
```

## 12. H5标签不可点击，Native不受影响

*iOS 11系统上，WKWebView内H5标签不可点击，Native不受影响。*

在频繁的切换页面、刷新WKWebView的情况下，会出现WKWebView卡死，所有的H5标签不可点击，Native的UI不受影响，TabBarVC的几个子控制器最为严重，有时候切换、刷新四五次左右，就会出现这种情况。

**更新：结论：在viewWillAppear方法中调用了`evaluateJavaScript: completionHandler:`方法，将该方法的调用移到viewDidAppear方法中即可。**

下面是探索的一些步骤，也走了一些弯路，可绕过：
> 分别从内存、视图、网络请求几个方面入手，按照以下步骤定位问题：
>
> 1. 对APP进行内存泄漏检测，优化了几处代码。毫无用处
>
> 2. WKWebView单独进程内存问题？因为有一些二级页面按照问题出现流程复现了N多次，都没有出现，所以暂时先排除
> 3. 网速问题。发现网速差时，确实很容易复现，网速好的时候，试了好几次没复现！做了一些网络优化，比如及时cancel掉一些不需要的请求，没有效果。
> 4. 视图加载、更新问题。猜测依据：一级页面更容易复现，且比二级页面多了一个Tabbar的视图。
> 5. 结论：结合第3、4，猜测是网络过慢时，tabbar出现、隐藏，及WKWebView刷新、加载、渲染HTML，几种情况结合导致的WKWebView布局混乱。
>
> 最后解决方法：包含WKWebView的一级页面，`viewDidAppear`时重新设置了一下WKWebView的约束。(设置UIScrollViewContentInsetAdjustmentAutomatic = YES，没有效果)
>
> 效果：大大改善了，但却没有根治问题。加了个保底方案，下拉刷新时，销毁旧WKWebView，创建新的，并loadRequest。(因为这些情况下iOS 11上出现的，且没有更低版本的测试机复现，所以暂时把修改限制在了iOS 11及以下的系统)

**最后**：有个最省事的方案，针对这些页面，**将WKWebView替换成UIWebView**。 可行，但逃避问题，不太可取，而且UIWebView、WKWebView各有一些特性，另一个不支持，比如WKWebView支持html，滚动时实时回调，而UIWebView只支持滚动停止时回调。且苹果已经不太支持UIWebView。还是早点拥抱WKWebView吧。
