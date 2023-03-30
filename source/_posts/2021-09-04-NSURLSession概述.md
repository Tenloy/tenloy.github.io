---
title: NSURLSession概述
date: 2021-09-04 08:53:12
urlname: nrl-session.html
algolia: false
categories:
  - 计算机网络
---

## 一、概述

NSURLSession 在iOS7中推出，旨在替换之前的NSURLConnection

- NSURLSession的使用相对于之前的NSURLConnection更简单，而且不用处理Runloop相关的东西；
- 暂停、停止、重启网络任务，不再需要 `NSOperation` 封装；
- 支持后台运行的网络任务；
- NSURLSession支持http2.0协议；
- 提供了全局的session并且可以统一配置，使用更加方便；
- 同一个session发送多次请求，只需要建立一次连接(复用了TCP)。

2015年 RFC 7540标准发布了http 2.0版本，http 2.0 版本中包含很多新的特性，在传输速度上也有很明显的提升。NSURLSession 从 iOS9.0 开始，对 http 2.0 提供了支持。

NSURLSession API 由三部分构成：

- NSURLSession：请求会话对象，可以用系统提供的单例对象，也可以自己创建。
  - 不同的 `session` 可以使用不同的私有存储。
- NSURLSessionConfiguration：对session会话进行配置，一般都采用default。
- NSURLSessionTask：负责执行具体请求的task，由session创建。使用同一个session的task可以共享连接和请求信息。

协议支持：

- NSURLSession 类支持data、file、ftp、http 和 https URL schemes，透明支持代理服务器和 SOCKS 网关，如用户系统首选项中配置的那样。
- NSURLSession 支持 HTTP/1.1、HTTP/2 和 HTTP/3 协议。 如 RFC 7540 所述，HTTP/2 支持需要支持应用层协议协商 (ALPN) 的服务器。
- 还可以通过继承 NSURLProtocol 来添加对开发者自定义的网络协议和 URL 方案的支持（供您的应用程序私人使用）。

线程安全：

- URL Session API 是线程安全的。 可以在任何线程上下文中自由创建 sessions 和 tasks。 当调用提供的 completion handlers 时，工作会自动安排在正确的 delegate queue 中。

## 二、NSURLSession

### 2.1 Session的创建

您的应用程序创建一个或多个 NSURLSession 实例，每个实例协调一组相关的数据传输任务。例如，如果您正在创建一个 Web 浏览器，您的应用程序可能会为每个选项卡或窗口创建一个会话，或者一个会话用于交互使用，另一个会话用于后台下载。在每个 session 中，可以添加一系列task，每个 task 都代表对特定 URL 的请求。

因为NSURLSession的TCP连接复用特性，所以尽量共用Session，以提升请求性能。

NSURLSession有三种方式创建。

#### 1. sharedSession

系统维护的一个单例对象。

```objc
// 使用当前设置的全局 NSURLCache、NSHTTPCookieStorage 和 NSURLCredentialStorage 对象。
@property (class, readonly, strong) NSURLSession *sharedSession;
```

#### 2. NSURLSessionConfiguration

在NSURLSession初始化时传入一个NSURLSessionConfiguration，这样可以自定义身份验证，超时时长，缓存策略，Cookie等配置。

```objc
+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration;
```

#### 3. delegate与delegate Queue

如果想更好的控制请求过程以及回调线程，可以使用下面的方法进行初始化操作，传入delegate、delegateQueue来设置回调对象和回调线程。

```objc
/*
 * @param queue 用于调度delegate methods、completion handlers的操作队列。队列应该是一个串行队列，以确保回调的正确顺序。 如果为 nil，则 session 创建一个串行操作队列。
 *              如果写主队列mainQueue，那么delegate、block就在主线程中运行；
 *              如果是[[NSOperationQueue alloc]init]、nil那么delegate、block就在子线程中运行。
 */
+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration 
                                  delegate:(nullable id <NSURLSessionDelegate>)delegate 
                             delegateQueue:(nullable NSOperationQueue *)queue;
```

如果你指定了一个delegate，**session对象保持对 delegate 的强引用**，直到应用退出或调用 invalidateAndCancel 或 finishTasksAndInvalidate 方法显式使会话无效，此时delegate被发送 `URLSession:didBecomeInvalidWithError:` 消息。

### 2.2 NSURLSessionConfigration

NSURLSessionConfiguration配置`NSURLSession`在网络交互过程中的各种属性。包括：身份验证，超时时长，缓存策略，Cookie等。

#### 2.2.1 创建方式

NSURLSessionConfiguration的创建，有三种方式：(注意：前两种方式不是单例方法，而是类方法，创建的是不同对象。各自的配置不会相互影响。)

```objectivec
/* 
* 普通模式（default）：使用基于磁盘(disk-based)的持久缓存（将结果下载到文件时除外）；将凭据(credentials)存储在用户的钥匙串(keychain)中；将cookie（默认情况下）存储在同一个共享cookie存储中。
*/
@property (class, readonly, strong) NSURLSessionConfiguration *defaultSessionConfiguration;
/*
 * 临时模式（ephemeral）：类似于defaultSessionConfiguration，不同之处在于不将缓存、凭证存储或任何与会话相关的数据存储到磁盘。
 */
@property (class, readonly, strong) NSURLSessionConfiguration *ephemeralSessionConfiguration;

/*
 * 后台模式（background）：允许在后台执行 HTTP 和 HTTPS 上传或下载
 * 使用此方法初始化适合在应用程序在后台运行时传输数据文件的配置对象。使用此对象配置的会话将传输控制权移交给系统，系统在单独的进程中处理传输。在 iOS 中，即使应用程序本身暂停或终止，此配置也可以继续传输。 
 * identifier: 配置对象的唯一标识符。此参数不得为 nil 或空字符串。一般用于恢复之前的任务，主要用于下载。
 * 详见-URLSessionDidFinishEventsForBackgroundURLSession:
 */
+ (NSURLSessionConfiguration *)backgroundSessionConfiguration:(NSString *)identifier; 
```

第三种方式创建的Task的应用：

- 在iOS中，当后台传输完成或需要凭据时，如果您的应用程序不再运行，您的应用程序会在后台自动重新启动，并且应用程序的 UIApplicationDelegate 会收到 `application:handleEventsForBackgroundURLSession:completionHandler:` 消息。此调用包含导致应用程序启动的session的identifier。
- 如果一个下载任务正在进行中，程序被kill，可以在程序退出之前保存identifier。下次进入程序后通过identifier恢复之前的任务，系统会将NSURLSession及NSURLSessionConfiguration和之前的下载任务进行关联，并继续之前的任务。(*后台能下载，手动kill可是不能继续下载的*)。[*详见文件下载一节*]()

**一般基本上都是使用默认设置。**

#### 2.2.2 属性预览

```objc
@property NSString                     * identifier;                 // identifier for the background session configuration
@property NSURLRequestCachePolicy        requestCachePolicy;         // cache策略
@property NSTimeInterval                 timeoutIntervalForRequest;  // 设置session请求间的超时时间，这个超时时间并不是请求从开始到结束的时间，而是两个数据包之间的时间间隔。当任意请求返回后这个值将会被重置，如果在超时时间内未返回则超时。单位为秒，默认为60秒。
@property NSTimeInterval                 timeoutIntervalForResource; // 资源超时时间，一般用于上传或下载任务，在上传或下载任务开始后计时，如果到达时间任务未结束，则删除资源文件。单位为秒，默认时间是七天。
@property NSURLRequestNetworkServiceType networkServiceType;
@property BOOL                           allowsCellularAccess;       // 是否允许访问蜂窝网
@property BOOL                           allowsExpensiveNetworkAccess;
@property BOOL                           allowsConstrainedNetworkAccess;
@property BOOL                           waitsForConnectivity;
@property (getter=isDiscretionary) BOOL  discretionary;                // 允许根据系统的判断来安排后台任务以获得最佳性能。
@property NSString                     * sharedContainerIdentifier;
@property BOOL                           sessionSendsLaunchEvents;     // 当后台会话中的任务完成或需要身份验证时，允许在后台恢复或启动应用程序。 这仅适用于使用 +backgroundSessionConfigurationWithIdentifier: 创建的配置，默认值为 YES。
@property NSDictionary                 * connectionProxyDictionary;
@property tls_protocol_version_t         TLSMinimumSupportedProtocolVersion;
@property tls_protocol_version_t         TLSMaximumSupportedProtocolVersion;
@property BOOL                           HTTPShouldUsePipelining;       // 会话是否应使用 HTTP 管道(pipelining)
@property BOOL                           HTTPShouldSetCookies;
@property NSHTTPCookieAcceptPolicy       HTTPCookieAcceptPolicy;
@property NSDictionary                 * HTTPAdditionalHeaders;         // 会话中发出的task的附加的header字段
@property NSHTTPCookieStorage          * HTTPCookieStorage;             // 会话中的cookie存储对象
@property NSURLCredentialStorage       * URLCredentialStorage;          // 会话中task使用的凭据存储对象
@property NSInteger                      HTTPMaximumConnectionsPerHost; // 最大连接数
@property NSURLCache                   * URLCache;                      // 为会话中的请求提供responses缓存
@property BOOL                           shouldUseExtendedBackgroundIdleMode;
@property NSArray<Class>               * protocolClasses;
@property NSURLSessionMultipathServiceType multipathServiceType;
```

附加说明：

- HTTPCookieStorage
  - 要禁用 cookie 存储，请将此属性设置为 nil。
  - 对于 default和 background sessions，默认值为 sharedHTTPCookieStorage cookie 存储对象。
  - 对于 ephemeralSessionConfiguration 会话，默认值是一个私有的 cookie 存储对象，它只将数据存储在内存中，并在您使会话无效时被销毁。
- URLCredentialStorage(基本同HTTPCookieStorage)
- URLCache
  - 要禁用缓存，请将此属性设置为 nil。
  - 对于默认会话，默认值为`sharedURLCache`。
  - 对于后台会话，默认值为 nil。
  - 对于临时会话，默认值是仅将数据存储在内存中的私有缓存对象，并在您使会话无效时被销毁。

#### 2.2.3 URLCache

`NSURLCache`提供了`Memory`和`Disk`的缓存，在创建时需要为其分别指定`Memory`和`Disk`的大小，以及存储的文件位置。使用`NSURLCache`不用考虑磁盘空间不够，或手动管理内存空间的问题，如果发生内存警告系统会自动清理内存空间。但是`NSURLCache`提供的功能非常有限，项目中一般很少直接使用它来处理缓存数据，还是用数据库比较多。

```objectivec
[[NSURLCache alloc] initWithMemoryCapacity:30 * 1024 * 1024 
                              diskCapacity:30 * 1024 * 1024 
                              directoryURL:[NSURL URLWithString:filePath]];
```

使用`NSURLCache`还有一个好处，就是可以由服务端来设置资源过期时间，在请求服务端后，服务端会返回`Cache-Control`来说明文件的过期时间。`NSURLCache`会根据`NSURLResponse`来自动完成过期时间的设置。

#### 2.2.4 HTTPMaximumConnectionsPerHost

此属性决定了根据本configuration创建的 sessions 中的任务与每个主机建立的最大同时连接数。

此限制是针对每个 session 的，因此如果使用了多个 session，那应用程序作为一个整体可能会超过此限制。 此外，根据与 Internet 的连接，session 使用的限制可能低于指定的限制。

但最好**不要为了增加并发而创建多个Session**，创建多个Session的目的应该是为了对不同的Task使用不同的策略，来实现更符合我们需求的交互。

macOS 中的默认值为 6，iOS 中的默认值为 4。

### 2.3 特性 — 连接复用

`HTTP`是基于传输层协议`TCP`的，通过`TCP`发送网络请求都需要先进行三次握手，建立网络请求后再发送数据，请求结束时再经历四次挥手。`HTTP1.0`开始支持`keep-alive`，`keep-alive`可以保持已经建立的链接，如果是相同的域名，在请求连接建立后，后面的请求不会立刻断开，而是复用现有的连接。从`HTTP1.1`开始默认开启`keep-alive`。

请求是在请求头中设置下面的参数，服务器如果支持`keep-alive`的话，响应客户端请求时，也会在响应头中加上相同的字段。

```objc
Connection: Keep-Alive
```

如果想断开`keep-alive`，可以在请求头中加上下面的字段，但一般不推荐这么做。

```objc
Connection: Close
```

如果通过`NSURLSession`来进行网络请求的话，需要**使用同一个 NSURLSession 对象，以复用 TCP 连接**（*很容易地就能通过抓包证明*）。如果创建新的`session`对象则不能复用之前的链接。`keep-alive`可以保持请求的连接，苹果允许在`iOS`上最大保持有4个连接，`Mac`则是6个连接。

### 2.4 特性 — pipeline

<img src="/images/net/urlsession/pipeline.jpg" style="zoom:80%;" />

在`HTTP1.1`中，基于`keep-alive`，还可以将请求进行管线化。和相同后端服务，`TCP`层建立的链接，一般都需要前一个请求返回后，后面的请求再发出。但`pipeline`就可以不依赖之前请求的响应，而发出后面的请求。

`pipeline`依赖客户端和服务器都有实现，服务端收到客户端的请求后，要按照先进先出的顺序进行任务处理和响应。`pipeline`依然存在之前非`pipeline`的问题，就是前面的请求如果出现问题，会阻塞当前连接影响后面的请求。

`pipeline`对于请求大文件并没有提升作用，只是对于普通请求速度有提升。在`NSURLSessionConfiguration`中可以设置`HTTPShouldUsePipelining`为`YES`，开启管线化，此属性默认为`NO`。

## 三、NSURLSessionTask

### 3.1 继承体系

通过NSURLSession发起的每个请求，都会被封装为一个NSURLSessionTask任务，但一般不会直接是NSURLSessionTask类，而是基于不同任务类型，被封装为其对应的子类。

```
     NSURLSessionTask
        |   \   \   \
        |    \   \   NSURLSessionWebSocketTask：通过 WebSockets 协议标准进行通信。
        |     \   NSURLSessionStreamTask      ：允许通过TCP/IP，可选的安全握手以及代理导航直接连接到给定的主机和端口。
        |   NSURLSessionDownloadTask          ：处理下载任务，获取下载进度，支持断点续传(暂停、取消、恢复。前提是服务器支持)
NSURLSessionDataTask  ：处理普通的Get、Post请求。
        |
NSURLSessionUploadTask：处理上传请求，可以传入对应的上传文件或路径。
```

主要方法都定义在父类NSURLSessionTask中。下面是一些关键方法或属性

```objc
@interface NSURLSessionTask : NSObject <NSCopying, NSProgressReporting>
//property
 currentRequest  // 当前正在执行的任务，一般和 originalRequest 是一样的，除非发生重定向才会有所区别。
 originalRequest // 主要用于重定向操作，用来记录重定向前的请求。
 taskIdentifier  // 当前session下，task的唯一标示，多个session之间可能存在相同的标识。
 priority        // task中可以设置优先级，但这个属性并不代表请求的优先级，而是一个标示。
                    // 官方已经说明，NSURLSession并没有提供API可以改变请求的优先级。
 state           // 当前任务的状态，可以通过KVO的方式监听状态的改变。

//method
-(void)resume;   // 开始或继续请求，创建后的task默认是挂起的，需要手动调用resume才可以开始请求。
-(void)suspend;  // 挂起当前请求。主要是下载请求用的多一些，普通请求挂起后都会重新开始请求。
                   // 下载请求挂起后，只要不超过NSURLRequest设置的timeout时间，调用resume就是继续请求。
-(void)cancel;   // 取消当前请求。任务会被标记为取消，并在未来某个时间调用URLSession:task:didCompleteWithError:方法。
@end
```

### 3.2 Task的创建

**所有的 task 创建出来默认都是suspended状态，必须调用 resume 方法开始任务。**

#### 3.2.1 代理回调方式

NSURLSession 提供有普通创建 task的方式，创建后可以通过重写代理方法，获取对应的回调和参数。这种方式对于请求过程比较好控制。

```objc
@interface NSURLSession : NSObject
  
/* Creates a data task */         // request: 提供特定请求的信息，例如URL、缓存策略、请求类型和body data或body stream.
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request;
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url;

/* Creates a upload task */
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromFile:(NSURL *)fileURL;
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromData:(NSData *)bodyData;
- (NSURLSessionUploadTask *)uploadTaskWithStreamedRequest:(NSURLRequest *)request;

/* Creates a download task */
- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request;
- (NSURLSessionDownloadTask *)downloadTaskWithURL:(NSURL *)url;
- (NSURLSessionDownloadTask *)downloadTaskWithResumeData:(NSData *)resumeData; // 实现断点续传 Creates task with resume data.

/* Creates a bidirectional(双向的) stream task to a given host and port. */
- (NSURLSessionStreamTask *)streamTaskWithHostName:(NSString *)hostname port:(NSInteger)port;

/* Creates a WebSocket task given the url. The given url must have a ws or wss scheme. (ws:// wss://) */
- (NSURLSessionWebSocketTask *)webSocketTaskWithURL:(NSURL *)url;
  // protocols将在 WebSocket 握手中用于与服务器协商首选协议
- (NSURLSessionWebSocketTask *)webSocketTaskWithURL:(NSURL *)url protocols:(NSArray<NSString *>*)protocols;
- (NSURLSessionWebSocketTask *)webSocketTaskWithRequest:(NSURLRequest *)request;
@end
```

#### 3.2.2 Block回调方式

除此之外，NSURLSession也提供了block的方式创建task，直接传入URL或NSURLRequest，即可直接在block中接收返回数据。

completionHandler和delegate是互斥的，**completionHandler的优先级大于delegate**。相对于普通创建方法，block方式更偏向于面向结果的创建，可以直接在completionHandler中获取返回结果，但不能控制请求过程。

```objectivec
/*
 * 1. 不适用于配置为后台会话(background sessions)的NSURLSession。
 * 2. 和普通创建方式一样，block的创建方式创建后默认也是suspend的状态，需要调用resume开始任务。
 * 3. 这些方法创建的任务会绕过delegate方法。
 */
@interface NSURLSession (NSURLSessionAsynchronousConvenience)
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request 
                            completionHandler:(void (^)(NSData*, NSURLResponse*, NSError*))completionHandler;
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url 
                        completionHandler:(void (^)(NSData*, NSURLResponse*, NSError*))completionHandler;

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request 
                                 fromFile:(NSURL *)fileURL 
                        completionHandler:(void (^)(NSData*, NSURLResponse*, NSError*))completionHandler;
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request 
                                 fromData:(nullable NSData *)bodyData 
                        completionHandler:(void (^)(NSData*, NSURLResponse*, NSError*))completionHandler;

- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request 
                        completionHandler:(void (^)(NSURL*, NSURLResponse*, NSError*))completionHandler;
- (NSURLSessionDownloadTask *)downloadTaskWithURL:(NSURL *)url 
                        completionHandler:(void (^)(NSURL*, NSURLResponse*, NSError*))completionHandler;
- (NSURLSessionDownloadTask *)downloadTaskWithResumeData:(NSData *)resumeData 
                        completionHandler:(void (^)(NSURL*, NSURLResponse*, NSError*))completionHandler;
@end
```

### 3.3 Task的获取

可以通过下面的两个方法，获取当前`session`对应的所有`task`：

```objc
@interface NSURLSession : NSObject
// 获取未完成的data、upload、download tasks.
- (void)getTasksWithCompletionHandler:(void (^)(NSArray<NSURLSessionDataTask *> *dataTasks, 
                                                NSArray<NSURLSessionUploadTask *> *uploadTasks, 
                                                NSArray<NSURLSessionDownloadTask *> *downloadTasks))completionHandler; 

// 获取所有未完成的tasks.
- (void)getAllTasksWithCompletionHandler:(void (^)(NSArray<__kindof NSURLSessionTask *> *tasks))completionHandler;
@end
```

`AFN`中，使用`getTasksWithCompletionHandler` 来获取当前`session`的`task`，并将`AFURLSessionManagerTaskDelegate`的回调都置为`nil`，以防止崩溃。

### 3.4 示例: 发起网络请求

通过NSURLSession发起一个网络请求：

```objectivec
// 1. 创建一个NSURLSessionConfiguration配置请求
NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
// 2. 通过Configuration创建NSURLSession对象
NSURLSession *session = [NSURLSession sessionWithConfiguration:config
                                                      delegate:self
                                                 delegateQueue:[NSOperationQueue mainQueue]];
// 3. 通过session对象发起网络请求，并获取task对象。
NSURLSessionDataTask *task = [session dataTaskWithURL:[NSURL URLWithString:@"http://www.baidu.com"]];
// 4. [task resume]方法发起网络请求。
[task resume];
```

## 四、Session、Task相关的代理方法

### 4.1 继承体系

`NSURLSession`中定义了一系列代理，并遵循上面的继承关系。父级代理定义的都是公共方法。

如果想执行某类任务、精细地控制请求和响应过程，只需要遵守Task对应的Delegate即可。例如：

- 执行普通`Post`、上传(`upload`)请求，则遵守`NSURLSessionDataDelegate`；
- 执行下载任务则遵循`NSURLSessionDownloadDelegate`

<img src="/images/net/urlsession/delegate.png" style="zoom:90%;" />

```objc
@protocol NSURLSessionDelegate <NSObject>
@optional
/* session收到的最后一条消息。session只会因为系统错误、显式设置为无效(此时error参数为nil)而变得无效   */
- (void)URLSession: didBecomeInvalidWithError:
/* 
 * 从代理请求凭据以响应来自远程服务器的会话级(session-level)身份验证请求。
 * 该方法在两种情况下调用：
 *   当远程服务器请求客户端证书或 Windows NT LAN Manager (NTLM) 身份验证时，以允许您的应用程序提供适当的凭据
 *   当会话首次与使用 SSL 或 TLS 的远程服务器建立连接时，以允许您的应用程序验证服务器的证书链
 * 如果您不实现此方法，会话将调用其委托的 URLSession:task:didReceiveChallenge:completionHandler: 方法。
 *
 * Session级别的didReceiveChallenge 与 Task级别的didReceiveChallenge 调用取决于身份认证挑战authentication challenge的类型：(值为challenge.protectionSpace.authenticationMethod)
 *  - 如果是会话级别的挑战(如下)，那么默认会调用session协议方法，如果其未实现，则调用task的didReceiveChallenge.
        NSURLAuthenticationMethodNTLM, 
        NSURLAuthenticationMethodNegotiate, 
        NSURLAuthenticationMethodClientCertificate,
        NSURLAuthenticationMethodServerTrust
 *  - 如果是非会话级别的挑战（所有其他），那么只会调用task的didReceiveChallenge。
 */
- (void)URLSession: didReceiveChallenge: completionHandler:
/*
 * 在iOS中，当后台传输完成或需要凭据时，如果您的应用程序不再运行，您的应用程序会在后台自动重新启动，并且应用程序的 UIApplicationDelegate 会收到 application:handleEventsForBackgroundURLSession:completionHandler: 消息。
 * 此调用包含导致应用程序启动的session的identifier。
 * 你应该存储这个completion handler。然后，你应该使用这个identifier创建一个background configuration对象，使用这个configuration创建一个session。新创建的session会自动与正在进行的后台活动重新关联。
 * 应用稍后收到 URLSessionDidFinishEventsForBackgroundURLSession: 消息，此时表明之前为此会话排队的所有消息都已传递。现在可以安全地调用先前存储的completionHandler或任何可能导致调用completionHandler的内部更新。
 * 重要的：因为completion handler是UIKit的一部分，所以必须在主线程上调用它。
 */
- (void)URLSessionDidFinishEventsForBackgroundURLSession:
@end

@protocol NSURLSessionTaskDelegate <NSURLSessionDelegate>
@optional
// 任务已完成数据传输
- (void)URLSession: task: didCompleteWithError: 
// 远程服务器请求了HTTP重定向。将request(可以修改)传入completionHandler完成重定向，或者传nil取消重定向。默认是遵循重定向。
- (void)URLSession: task: willPerformHTTPRedirection: newRequest: completionHandler: 
// 定期通知delegate：向服务器发送正文内容的进度。(比如文件上传时监听进度)
- (void)URLSession: task: didSendBodyData: totalBytesSent: totalBytesExpectedToSend: 
// task需要一个request body stream发送到远程服务器
- (void)URLSession: task: needNewBodyStream: 
// 从代理请求凭据以响应来自远程服务器的身份验证请求
- (void)URLSession: task: didReceiveChallenge: completionHandler: 
// 延迟的URL session task 现在将开始加载
- (void)URLSession: task: willBeginDelayedRequest: completionHandler: 
// 任务正在等待，直到合适的连接可用
- (void)URLSession: taskIsWaitingForConnectivity: 
// session已完成task的metrics收集。（可以得到一个NSURLSessionTaskMetrics对象，封装了task的网络连接的详细指标信息）
- (void)URLSession: task: didFinishCollectingMetrics: 
@end

@protocol NSURLSessionDataDelegate <NSURLSessionTaskDelegate>
@optional
// 从服务器接收到初始回复（headers）
- (void)URLSession: dataTask: didReceiveResponse: completionHandler: 
// data task 被更改为 download task.
- (void)URLSession: dataTask: didBecomeDownloadTask: 
// data task 被更改为 stream task.
- (void)URLSession: dataTask: didBecomeStreamTask: 
// 已收到一些预期的数据
- (void)URLSession: dataTask: didReceiveData: 
// 询问delegate对象：dataTask/uploadTask是否应将响应存储在缓存中。
- (void)URLSession: dataTask: willCacheResponse: completionHandler: 
@end

@protocol NSURLSessionDownloadDelegate <NSURLSessionTaskDelegate>
/* 已完成下载. 
 * @param location 是临时文件的URL。由于是临时文件，所以必须打开文件进行读取或将其移动到应用程序沙箱容器目录中的永久位置，然后才能从此委托方法返回。（应该在另一个线程中进行实际读取以避免阻塞委托队列）
 */
- (void)URLSession: downloadTask: didFinishDownloadingToURL:(NSURL *)location;
@optional
/* 已恢复下载.
 * @param offset: 如果文件的缓存策略或上次修改日期阻止重复使用现有内容，则此值为零。否则，此值是一个整数，表示磁盘上不需要再次拉取的字节数。
 * @param expectedTotalBytes: 文件的预期长度，由Content-Length header提供。如果未提供此标头，则值为 NSURLSessionTransferSizeUnknown
 */
- (void)URLSession: downloadTask: didResumeAtOffset: expectedTotalBytes: 
// 定期通知代理下载进度
- (void)URLSession: downloadTask: didWriteData: totalBytesWritten: totalBytesExpectedToWrite: 
@end

@protocol NSURLSessionStreamDelegate <NSURLSessionTaskDelegate>
@optional
// 已为流检测到 到主机的更好路由
- (void)URLSession: betterRouteDiscoveredForStreamTask: 
// 由于streamTask调用 captureStreams 方法，task已完成
- (void)URLSession: streamTask: didBecomeInputStream: outputStream: 
// 底层套接字(socket)的读取端已关闭
- (void)URLSession: readClosedForStreamTask: 
// 底层套接字(socket)的写入端已关闭
- (void)URLSession: writeClosedForStreamTask: 
@end

@protocol NSURLSessionWebSocketDelegate <NSURLSessionTaskDelegate>
@optional
// WebSocket task成功地与端点(endpoint)协商握手(negotiated the handshake) 。指示协商的协议。
- (void)URLSession: webSocketTask: didOpenWithProtocol: 
// Websocket task从服务器端点接收了一个close frame，可选地包括服务器的关闭code和原因.
- (void)URLSession: webSocketTask: didCloseWithCode: reason: 
@end
```

### 4.2 示例: 请求重定向

`HTTP`协议中定义了例如301等重定向状态码，通过下面的代理方法，可以处理重定向任务。

- 可以根据`response`创建一个新的`request`，也可以直接用系统生成的`request`，并在`completionHandler`回调中传入，完成这次重定向。
- 如果想终止这次重定向，在`completionHandler`传入`nil`即可。

```objectivec
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest *))completionHandler
{
    NSURLRequest *redirectRequest = request;

    if (self.taskWillPerformHTTPRedirection) {
        redirectRequest = self.taskWillPerformHTTPRedirection(session, task, response, request);
    }

    if (completionHandler) {
        completionHandler(redirectRequest);
    }
}
```

## 五、NSURLSessionTaskMetrics

在日常开发过程中，经常遇到页面加载太慢的问题，这很大一部分原因都是因为网络导致的。所以，查找网络耗时的原因并解决，就是一个很重要的任务了。苹果对于网络检查提供了`NSURLSessionTaskMetrics`类来进行检查，`NSURLSessionTaskMetrics`是对应`NSURLSessionTaskDelegate`的，每个task结束时都会回调下面的方法，并且可以获得一个`metrics`对象。

```objectivec
- (void)URLSession:(NSURLSession *)session 
              task:(NSURLSessionTask *)task 
didFinishCollectingMetrics:(NSURLSessionTaskMetrics *)metrics;
```

`NSURLSessionTaskMetrics`可以很好的帮助我们分析网络请求的过程，以找到耗时原因。除了这个类之外，`NSURLSessionTaskTransactionMetrics`类中承载了更详细的数据。

```objectivec
@interface NSURLSessionTaskMetrics : NSObject
// 数组中每一个元素都对应着当前 task 的一个请求，一般数组中只会有一个元素，如果发生重定向等情况，可能会存在多个元素。
@property NSArray<NSURLSessionTaskTransactionMetrics *> *transactionMetrics;
// 任务被实例化和任务完成之间的时间间隔
@property NSDateInterval *taskInterval;
// 任务执行期间，重定向次数，在进行下载请求时一般都会进行重定向，来保证下载任务能由后端最合适的节点来处理。
@property NSUInteger redirectCount; 
@end
```

### 5.1 TransactionMetrics

`NSURLSessionTaskTransactionMetrics`中的属性都是用来做统计的，功能都是记录某个值，并没有逻辑上的意义。所以这里就对一些主要的属性做一下解释，基本涵盖了大部分属性，其他就不管了。

下面这张网图，标示了`NSURLSessionTaskTransactionMetrics`的属性在请求过程中处于什么位置。

![请求耗时细节](/images/net/urlsession/metrics.jpg)

```objectivec
// 请求对象
@property (copy, readonly) NSURLRequest *request;
// 响应对象，请求失败可能会为nil
@property (nullable, copy, readonly) NSURLResponse *response;
// 请求开始时间
@property (nullable, copy, readonly) NSDate *fetchStartDate;
// DNS解析开始时间
@property (nullable, copy, readonly) NSDate *domainLookupStartDate;
// DNS解析结束时间，如果解析失败可能为nil
@property (nullable, copy, readonly) NSDate *domainLookupEndDate;
// 开始建立TCP连接时间
@property (nullable, copy, readonly) NSDate *connectStartDate;
// 结束建立TCP连接时间
@property (nullable, copy, readonly) NSDate *connectEndDate;
// 开始TLS握手时间
@property (nullable, copy, readonly) NSDate *secureConnectionStartDate;
// 结束TLS握手时间
@property (nullable, copy, readonly) NSDate *secureConnectionEndDate;
// 开始传输请求数据时间
@property (nullable, copy, readonly) NSDate *requestStartDate;
// 结束传输请求数据时间
@property (nullable, copy, readonly) NSDate *requestEndDate;
// 接收到服务端响应数据时间
@property (nullable, copy, readonly) NSDate *responseStartDate;
// 服务端响应数据传输完成时间
@property (nullable, copy, readonly) NSDate *responseEndDate;
// 网络协议，例如http/1.1
@property (nullable, copy, readonly) NSString *networkProtocolName;
// 请求是否使用代理
@property (assign, readonly, getter=isProxyConnection) BOOL proxyConnection;
// 是否复用已有连接
@property (assign, readonly, getter=isReusedConnection) BOOL reusedConnection;
// 资源标识符，表示请求是从Cache、Push、Network哪种类型加载的
@property (assign, readonly) NSURLSessionTaskMetricsResourceFetchType resourceFetchType;
// 本地IP
@property (nullable, copy, readonly) NSString *localAddress;
// 本地端口号
@property (nullable, copy, readonly) NSNumber *localPort;
// 远端IP
@property (nullable, copy, readonly) NSString *remoteAddress;
// 远端端口号
@property (nullable, copy, readonly) NSNumber *remotePort;
// TLS协议版本，如果是http则是0x0000
@property (nullable, copy, readonly) NSNumber *negotiatedTLSProtocolVersion;
// 是否使用蜂窝数据
@property (readonly, getter=isCellular) BOOL cellular;
```

## 六、NSURLSession文件上传

### 6.1 表单上传

上传文件现在主流的方式，都是采取表单上传的方式，也就是`multipart/from-data`，`AFNetworking`对表单上传也有很有的支持。

常见的几种`Content-Type`：

```c
Content-Type: text/html; charset=utf-8
Content-Type: application/json                   // json格式 {key:value}
Content-Type: application/x-www-form-urlencoded  // urlencode格式 key=value&key=value
Content-Type: multipart/form-data; boundary=something // 文件上传
```

#### 6.1.1 form-data数据格式

表单上传需要遵循下面的格式进行上传：（`multipart/form-data`规范定义在[rfc2388](https://www.ietf.org/rfc/rfc2388.txt)，详细字段可以看一下规范）

- `multipart/form-data`：表示包含了一系列的部分(parts)。 每个part都应包含一个`content-disposition` header，值为`form-data`；包含 `name` 参数，值为表单(form)中的原始字段名称。 
  - multipart/form-data只是multipart的一种。其他的比如multipart/mixed, multipart/related和multipart/alternative等
- `boundary`: 是一个16进制字符串，可以是任何且唯一的。`boundary`的功能用来进行字段分割，区分开不同的参数部分。
- `name`: 是一个表单字段名，每一个字段名会对应一个子部分。在同一个字段名对应多个文件的情况下，则多个子部分共用同一个字段名。
- `filename`：是要传送的文件的初始名称的字符串。这个参数总是可选的，而且不能盲目使用：路径信息必须舍掉，同时要进行一定的转换以符合服务器文件系统规则。
  - 这个参数主要用来提供展示性信息。
  - 当与 Content-Disposition: attachment 一同使用的时候，它被用作"保存为"对话框中呈现给用户的默认文件名。

```objectivec
--boundary
Content-Disposition: form-data; name="参数名"
  
参数值
--boundary
Content-Disposition:form-data;name="表单控件名";filename="上传文件名"
Content-Type:mime type
  
要上传文件二进制数据
--boundary--
```

拼接上传文件基本上可以分为下面三部分，上传参数、上传信息、上传文件。并且通过`UTF-8`格式进行编码，服务端也采用相同的解码方式，则可以获得上传文件和信息。需要注意的是，**换行符数量是固定的**，这都是固定的协议格式，不要多或者少，会导致服务端解析失败。

```objectivec
- (NSData *)writeMultipartFormData:(NSData *)data 
                        parameters:(NSDictionary *)parameters {
    if (data.length == 0) {
        return nil;
    }
    
    NSMutableData *formData = [NSMutableData data];
    NSData *lineData = [@"\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *boundary = [kBoundary dataUsingEncoding:NSUTF8StringEncoding];
    
    // 拼接上传参数
    [parameters enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        [formData appendData:boundary];
        [formData appendData:lineData];
        NSString *thisFieldString = [NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n%@", key, obj];
        [formData appendData:[thisFieldString dataUsingEncoding:NSUTF8StringEncoding]];
        [formData appendData:lineData];
    }];
    
    // 拼接上传信息
    [formData appendData:boundary];
    [formData appendData:lineData];
    NSString *thisFieldString = [NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\nContent-Type: %@", @"name", @"filename", @"mimetype"];
    [formData appendData:[thisFieldString dataUsingEncoding:NSUTF8StringEncoding]];
    [formData appendData:lineData];
    [formData appendData:lineData];
    
    // 拼接上传文件
    [formData appendData:data];
    [formData appendData:lineData];
    [formData appendData: [[NSString stringWithFormat:@"--%@--\r\n", kBoundary] dataUsingEncoding:NSUTF8StringEncoding]];
    
    return formData;
}
```

<img src="/images/net/urlsession/form-data.png" alt="form-data" style="zoom:90%;" />

#### 6.1.2 header设置

除此之外，表单提交还需要设置请求头的`Content-Type`和`Content-Length`。

- 设置`Content-Type`时，一定要加上`boundary`，这个`boundary`和拼接上传文件的`boundary`需要是同一个。服务端从请求头拿到`boundary`，来解析上传文件。
- `Content-Length`并不是强制要求的，要看后端的具体支持情况。

```objectivec
NSString *headerField = [NSString stringWithFormat:@"multipart/form-data; charset=utf-8; boundary=%@", kBoundary];
[request setValue:headerField forHTTPHeaderField:@"Content-Type"];

NSUInteger size = [[[NSFileManager defaultManager] attributesOfItemAtPath:uploadPath error:nil] fileSize];
headerField = [NSString stringWithFormat:@"%lu", size];
[request setValue:headerField forHTTPHeaderField:@"Content-Length"];
```

#### 6.1.3 创建NSURLSessionUploadTask

随后我们通过下面的代码创建`NSURLSessionUploadTask`，并调用`resume`发起请求，实现对应的代理回调即可。

```objectivec
// 发起网络请求
NSURLSessionUploadTask *uploadTask = [self.backgroundSession uploadTaskWithRequest:request fromData:fromData];
[uploadTask resume];
    
// 请求完成后调用，无论成功还是失败
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    
}

// 更新上传进度，会回调多次
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
   didSendBodyData:(int64_t)bytesSent
    totalBytesSent:(int64_t)totalBytesSent
totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend {
    
}

// 数据接收完成回调
- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {
    
}

// 处理后台上传任务，当前session的上传任务结束后会回调此方法。
- (void)URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session {
    
}
```

### 6.2 分片上传

客户端有时候需要给服务端上传大文件，进行大文件肯定不能全都加载到内存里，一口气都传给服务器。进行大文件上传时，一般都会对需要上传的文件进行分片，分片后逐个文件进行上传。需要注意的是，分片上传和断点续传并不是同一个概念，上传并不支持断点续传。

进行分片上传时，需要对本地文件进行读取，我们使用`NSFileHandle`来进行文件读取。`NSFileHandle`提供了一个偏移量的功能，我们可以将`handle`的当前读取位置`seek`到上次读取的位置，并设置本次读取长度，读取的文件就是我们指定文件的字节。

```objectivec
- (NSData *)readNextBuffer {
    if (self.maxSegment <= self.currentIndex) {
        return nil;
    }
    
    if(!self.fileHandler){
        NSString *filePath = [self uploadFile];
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:filePath];
        self.fileHandler = fileHandle;
    }
    [self.fileHandler seekToFileOffset:(self.currentIndex) * self.segmentSize];
    NSData *data = [self.fileHandler readDataOfLength:self.segmentSize];
    return data;
}
```

### 6.3 动态分片

用户在上传时网络环境会有很多情况，`WiFi`、4G、弱网等很多情况。如果上传分片太大可能会导致失败率上升，分片文件太小会导致网络请求太多，产生太多无用的`boundary`、`header`、数据链路等资源的浪费。

为了解决这个问题，我们采取的是动态分片大小的策略。根据特定的计算策略，预先使用第一个分片的上传速度当做测速分片，测速分片的大小是固定的。根据测速的结果，对其他分片大小进行动态分片，这样可以保证分片大小可以最大限度的利用当前网速。

当然，如果觉得这种分片方式太过复杂，也可以采取一种阉割版的动态分片策略。即根据网络情况做判断，如果是`WiFi`就固定某个分片大小，如果是流量就固定某个分片大小。然而这种策略并不稳定，因为现在很多手机的网速比`WiFi`还快，我们也不能保证`WiFi`都是百兆光纤。

```objectivec
if ([Reachability reachableViaWiFi]) {
    self.segmentSize = 500 * 1024;
} else if ([Reachability reachableViaWWAN]) {
    self.segmentSize = 300 * 1024;
}
```

### 6.4 并行上传

上传的所有任务如果使用的都是同一个`NSURLSession`的话，是可以保持连接的，省去建立和断开连接的消耗。在`iOS`平台上，`NSURLSession`支持对一个`Host`保持4个连接，所以，如果我们采取并行上传，可以更好的利用当前的网络。

并行上传的数量在`iOS`平台上不要超过4个，最大连接数是可以通过`NSURLSessionConfiguration`设置的，而且数量最好不要写死。同样的，应该基于当前网络环境，在上传任务开始的时候就计算好最大连接数，并设置给`Configuration`。

经过我们的线上用户数据分析，在线上环境使用并行任务的方式上传，上传速度相较于串行上传提升四倍左右。计算方式是每秒文件上传的大小。

```objectivec
iPhone串行上传：715 kb/s
iPhone并行上传：2909 kb/s
```

### 6.5 队列管理

分片上传过程中可能会因为网速等原因，导致上传失败。失败的任务应该由单独的队列进行管理，并且在合适的时机进行失败重传。

例如对一个500MB的文件进行分片，每片是300KB，就会产生1700多个分片文件，每一个分片文件就对应一个上传任务。如果在进行上传时，一口气创建1700多个`uploadTask`，尽管`NSURLSession`是可以承受的，也不会造成一个很大的内存峰值。但这样并不太好，实际上并不会同时有这么多请求发出。

```objectivec
/// 已上传成功片段数组
@property (nonatomic, strong) NSMutableArray *successSegments;
/// 待上传队列的数组
@property (nonatomic, strong) NSMutableArray *uploadSegments;
```

所以在创建上传任务时，可设置一个最大任务数，就是同时向`NSURLSession`发起的请求不会超过这个数量。需要注意的是，这个数值是创建`uploadTask`的任务数，并不是最大并发数，最大并发数由`NSURLSession`来控制。

将待上传任务都放在`uploadSegments`中，上传成功后从待上传任务数组中取出一条或多条，并保证同时进行的任务始终不超过最大任务数。失败的任务理论上来说也是需要等待上传的，所以把失败任务也放在`uploadSegments`中，插入到队列最下面，这样就保证了待上传任务完成后，继续重试失败任务。

将成功的任务放在`successSegments`中，并且始终保持和`uploadSegments`没有交集。两个队列中保存的并不是`uploadTask`，而是分片的索引，这也是为什么给分片命名的时候用索引做名字。当`successSegments`等于分片数量时，就表示所有任务上传完成。

## 七、NSURLSession文件下载

### 7.1 普通下载

> [iOS 原生级别后台下载详解](https://juejin.cn/post/6844903768916492295#heading-14)

和上传代码一样，创建下载任务很简单，通过`NSURLSession`创建一个`downloadTask`，并调用`resume`即可开启一个下载任务。

```objectivec
NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
NSURLSession *session = [NSURLSession sessionWithConfiguration:config 
                                                      delegate:self 
                                                 delegateQueue:[NSOperationQueue mainQueue]];

NSURL *url = [NSURL URLWithString:@"http://vfx.mtime.cn/Video/2017/03/31/mp4/170331093811717750.mp4"];
NSURLRequest *request = [[NSURLRequest alloc] initWithURL:url];
NSURLSessionDownloadTask *downloadTask = [session downloadTaskWithRequest:request];
[downloadTask resume];
```

我们可以调用`suspend`将下载任务挂起，随后调用`resume`方法继续下载任务，`suspend`和`resume`需要是成对的。

但是`suspend`挂起任务是有超时的，默认为60s，如果超时系统会将`TCP`连接断开，我们再调用`resume`是失效的。可以通过`NSURLSessionConfiguration`的`timeoutIntervalForResource`来设置上传和下载的资源耗时。`suspend`只针对于下载任务，其他任务挂起后将会重新开始。

下面两个方法是下载比较基础的方法，分别用来接收下载进度和下载完的临时文件地址。

```objectivec
// 从服务器接收数据，下载进度回调
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask
             didWriteData:(int64_t)bytesWritten              // 此次下载了多少
        totalBytesWritten:(int64_t)totalBytesWritten         // 到目前为止,一共下载了多少
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite // 服务器文件的大小 
{
    CGFloat progress = (CGFloat)totalBytesWritten / (CGFloat)totalBytesExpectedToWrite;
    self.progressView.progress = progress;
}

// 下载完成后回调（@required必须实现）
// 当下载结束后下载文件被写入在 Library/Caches下的一个临时文件，我们需要将此文件移动到自己的目录，临时目录在未来的一个时间会被删掉。
- (void)URLSession:(NSURLSession *)session 
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location 
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    //要拷贝到的路径
    NSString *filePath = [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:@"123.zip"];
    NSURL *fileURL = [NSURL fileURLWithPath:filePath];
  
    [fileManager copyItemAtURL:location toURL:fileURL error:NULL];
}
```

### 7.2 断点续传

`HTTP`协议支持断点续传操作，在开始下载请求时通过请求头设置`Range`字段，标示从什么位置开始下载。

```objectivec
Range:bytes=512000-
```

服务端收到客户端请求后，开始从512kb的位置开始传输数据，并通过`Content-Range`字段告知客户端传输数据的起始位置。

```objectivec
Content-Range:bytes 512000-/1024000
```

`downloadTask`任务开始请求后，可以调用`cancelByProducingResumeData:`方法可以取消下载，并且可以获得一个`resumeData`，`resumeData`中存放一些断点下载的信息。可以将`resumeData`写到本地，后面通过这个文件可以进行断点续传。

```objectivec
NSString *library = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
NSString *resumePath = [library stringByAppendingPathComponent:[self.downloadURL md5String]];
[self.downloadTask cancelByProducingResumeData:^(NSData * _Nullable resumeData) {
    [resumeData writeToFile:resumePath atomically:YES];
}];
```

在创建下载任务前，可以判断当前任务有没有之前待恢复的任务，如果有的话调用`downloadTaskWithResumeData:`方法并传入一个`resumeData`，可以恢复之前的下载，并重新创建一个`downloadTask`任务。

```objectivec
NSString *library = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
NSString *resumePath = [library stringByAppendingPathComponent:[self.downloadURL md5String]];
NSData *resumeData = [[NSData alloc] initWithContentsOfFile:resumePath];
self.downloadTask = [self.session downloadTaskWithResumeData:resumeData];
[self.downloadTask resume];
```

通过`suspend`和`resume`这种方式挂起的任务，`downloadTask`是同一个对象，而通过`cancel`然后`resumeData`恢复的任务，会创建一个新的`downloadTask`任务。

当调用`downloadTaskWithResumeData:`方法恢复下载后，会回调下面的方法。

```objc
- (void)URLSession:(NSURLSession *)session 
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
 didResumeAtOffset:(int64_t)fileOffset           // 上次文件的下载大小
expectedTotalBytes:(int64_t)expectedTotalBytes;  // 预估的文件总大小。
```

### 7.3 后台下载

#### 7.3.1 可后台下载的downloadTask

`NSURLSession`是在单独的进程中运行，所以通过此类发起的网络请求，是独立于应用程序运行的，即使App挂起也不会停止请求。

通过`backgroundSessionConfigurationWithIdentifier`方法创建后台上传或后台下载类型的`NSURLSessionConfiguration`，并且设置一个唯一标识，需要保证这个标识在不同的`session`之间的唯一性。后台任务只支持`http`和`https`的任务，其他协议的任务并不支持。

```objc
// 如果需要实现后台下载，就必须创建Background Sessions
NSURLSessionConfiguration *config = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:@"identifier"];
config.isDiscretionary = YES; // // 当后台会话中的任务完成或需要身份验证时，允许在后台恢复或启动应用程序。这仅适用于使用 +backgroundSessionConfigurationWithIdentifier: 创建的配置，默认值为 YES。
config.sessionSendsLaunchEvents = YES;
NSURLSession * session =[NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:[NSOperationQueue mainQueue]];

// 通过Background Sessions 创建出来的 downloadTask ，其实是 __NSCFBackgroundDownloadTask
NSURLSessionDownloadTask *downloadTask = [session downloadTaskWithRequest:request];
```

通过这种方式创建的`URLSession`，其实是`__NSURLBackgroundSession`：

- 必须使用`background(withIdentifier:)`方法创建`URLSessionConfiguration`，其中这个`identifier`必须是固定的，而且为了避免跟其他 App 冲突，建议这个`identifier`跟 App 的`Bundle ID`相关
- 创建`URLSession`的时候，必须传入`delegate`
- 必须在 App 启动的时候创建`Background Sessions`，即它的生命周期跟 App 几乎一致，为方便使用，最好是作为`AppDelegate`的属性，或者是全局变量

当应用进入到后台时，可以继续下载，如果客户端没有开启`Background Mode`，则不会回调客户端进度。下次进入前台时，会继续回调新的进度。

#### 7.3.2 APP生命周期改变对Task的影响

支持后台下载的 downloadTask 在不同情况下的表现：

| <div style="width:150px">操作</div> | <div style="width:420px">创建</div>                          | <div style="width:420px">运行中</div>                        | <div style="width:600px">暂停（suspend）</div>               | <div style="width:400px">取消（cancel(byProducingResumeData:)）</div> | <div style="width:300px">取消（cancel）</div>                |
| ----------------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------ | ------------------------------------------------------------ | ------------------------------------------------------------ | ------------------------------------------------------------ |
| 立即产生的效果                      | 在 App 沙盒的 caches 文件夹里面创建 tmp 文件                 | 把下载的数据写入 caches 文件夹里面的 tmp 文件                | caches 文件夹里面的 tmp 文件不会被移动                       | caches 文件夹里面的 tmp 文件会被移动到 Tmp 文件夹；<br />会调用 didCompleteWithError | caches 文件夹里面的tmp 文件会被删除；<br />会调用 didCompleteWithError |
| 进入后台                            | 自动开启下载                                                 | 继续下载                                                     | 没有发生任何事情                                             | 没有发生任何事情                                             | 没有发生任何事情                                             |
| 手动kill App                        | caches 文件夹里面的 tmp 文件会被删除；<br />重新打开 App 后创建相同 identifier 的 session，会调用 didCompleteWithError（等于调用了 cancel） | 下载停止了；<br />*然后操作同右列*。                         | caches 文件夹里面的 tmp 文件不会被移动；<br />重新打开 App 后创建相同 identifier 的 session，tmp 文件会被移动到 Tmp 文件夹；<br />会调用 didCompleteWithError（等于调用了 cancel(byProducingResumeData:)） | 没有发生任何事情                                             | 没有发生任何事情                                             |
| crash或者被系统关闭                 | 自动开启下载；<br />caches 文件夹里面的 tmp 文件不会被移动；<br />重新打开 App 后，不管是否有创建相同 identifier 的 session，都会继续下载（保持下载状态） | 继续下载；<br />caches 文件夹里面的 tmp 文件不会被移动；<br />重新打开 App 后，不管是否有创建相同 identifier 的 session，都会继续下载（保持下载状态） | caches 文件夹里面的 tmp 文件不会被移动；<br />重新打开 app 后创建相同 identifier 的 session，不会调用 didCompleteWithError；<br />session 里面还保存着 task，此时task还是暂停状态，可以恢复下载 | 没有发生任何事情                                             | 没有发生任何事情                                             |

#### 7.3.3 下载完成时

由于支持后台下载，下载任务完成时，App 有可能处于不同状态，所以还要了解对应的表现：

- 在前台：跟普通的 downloadTask 一样，调用相关的 session 代理方法
- 在后台：
  - 当`Background Sessions`里面所有的任务（注意是所有任务，不单单是下载任务）都完成后，会调用`AppDelegate`的`application(_:handleEventsForBackgroundURLSession:completionHandler:)`方法，激活 App；
  - 然后跟在前台时一样，调用相关的 session 代理方法；
  - 最后再调用`urlSessionDidFinishEvents(forBackgroundURLSession:)`方法
- crash 或者 App 被系统关闭：
  - 当`Background Sessions`里面所有的任务（注意是所有任务，不单单是下载任务）都完成后，会自动启动 App，调用`AppDelegate`的`application(_:didFinishLaunchingWithOptions:)`方法；
  - 然后调用`application(_:handleEventsForBackgroundURLSession:completionHandler:)`方法
  - 当**根据 identifier 创建了对应的Background Sessions** 后，才会跟在前台时一样，调用相关的 session 代理方法，
  - 最后再调用`urlSessionDidFinishEvents(forBackgroundURLSession:)`方法
- crash 或者 App 被系统关闭，打开 App 保持前台，当所有的任务都完成后才创建对应的`Background Sessions`：
  - 没有创建 session 时，只会调用`AppDelegate`的`application(_:handleEventsForBackgroundURLSession:completionHandler:)`方法；
  - 当创建了对应的`Background Sessions`后，才会跟在前台时一样，调用相关的 session 代理方法，最后再调用`urlSessionDidFinishEvents(forBackgroundURLSession:)`方法
- crash 或者 App 被系统关闭，打开 App，创建对应的`Background Sessions`后所有任务才完成：跟在前台的时候一样

总结：

- 只要不在前台，当所有任务完成后会调用`AppDelegate`的`application(_:handleEventsForBackgroundURLSession:completionHandler:)`方法
- 只有创建了对应`Background Sessions`，才会调用对应的 session 代理方法，如果不在前台，还会调用`urlSessionDidFinishEvents(forBackgroundURLSession:)`

具体处理方式：

首先就是`Background Sessions`的创建时机，前面说过：

> 必须在 App 启动的时候创建`URLSession`，即它的生命周期跟 App 几乎一致，为方便使用，最好是作为`AppDelegate`的属性，或者是全局变量。

原因：下载任务有可能在 App 处于不同状态时完成，所以需要保证 App 启动的时候，`Background Sessions`也已经创建，这样才能使它的代理方法正确的调用，并且方便接下来的操作。

根据下载任务完成时的表现，结合苹果官方文档：

```swift
// 必须在AppDelegate中，实现这个方法
/* 
 * 在iOS中，当后台传输完成或需要凭据时，如果您的应用程序不再运行，您的应用程序会在后台自动重新启动，并回调UIApplicationDelegate的下面方法。
 * session是否存在：
 *   若存在：调用相关的 session 代理方法，最后再调用urlSessionDidFinishEvents(forBackgroundURLSession:)方法
 *   若不存在，可使用这个identifier创建一个background configuration对象，使用这个configuration创建一个session。新创建的session会自动与正在进行的后台活动重新关联。然后同上，先调用session代理方法，再调用...
 * 
 * @param identifier 对应Background Sessions的identifier。
 * @param completionHandler 当完成事件处理时调用。通知系统你的应用程序的用户界面已更新，可以拍摄新的快照(snapshot)。
 *                          你应该存储这个completionHandler。handler是UIKit的一部分，所以必须在主线程上调用它。
 */
func application(_ application: UIApplication,
                 handleEventsForBackgroundURLSession identifier: String,
                 completionHandler: @escaping () -> Void) {
    	if identifier == urlSession.configuration.identifier ?? "" {
            // 这里用作为AppDelegate的属性，保存completionHandler
            backgroundCompletionHandler = completionHandler
	    }
      // 如果有多个background session，那需要找到该identifier对应的，即completionHandler要与session匹配起来。当session的代理方法中，此session的处理执行完，执行completionHandler
      // for manager in downloadManagers {
      //     if manager.identifier == identifier {
      //         manager.completionHandler = completionHandler
      //         break
      //     }
      // }
}
```

然后要在 session 的代理方法里调用`completionHandler` ：

```swift
// 应用稍后收到 URLSessionDidFinishEventsForBackgroundURLSession: 消息。这表明之前为此会话排队的所有消息都已传递。
// 现在可以安全地调用先前存储的completionHandler或开始任何可能导致调用completionHandler的内部更新。
// 必须实现这个方法，并且在主线程调用completionHandler
func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    guard let appDelegate = UIApplication.shared.delegate as? AppDelegate,
        let backgroundCompletionHandler = appDelegate.backgroundCompletionHandler else { return }
        
    DispatchQueue.main.async {
        // 上面保存的completionHandler
        backgroundCompletionHandler()
    }
}
```

至此，下载完成的情况也处理完毕。

后台下载过程中会设计到一系列的代理方法调用，下面是时序图。

![后台下载时序图](/images/net/urlsession/bg-download.png)

#### 7.3.4 下载错误时

支持后台下载的 downloadTask 失败的时候，在`urlSession(_:task:didCompleteWithError:)`方法里面的`(error as NSError).userInfo`可能会出现一个 key 为`NSURLErrorBackgroundTaskCancelledReasonKey`的键值对，由此可以获得只有后台下载任务失败时才有相关的信息，具体请看：[Background Task Cancellation](https://link.juejin.cn?target=https%3A%2F%2Fdeveloper.apple.com%2Fdocumentation%2Ffoundation%2Furlsession%2F1508626-background_task_cancellation)

```swift
func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if let error = error {
        let backgroundTaskCancelledReason = (error as NSError).userInfo[NSURLErrorBackgroundTaskCancelledReasonKey] as? Int
    }
}
```

#### 7.3.5 错误汇总

如果重复后台已经存在的下载任务，会提示这个错误。

```objectivec
A background URLSession with identifier backgroundSession already exists
```

需要在页面退出或程序退出时，调用`finishTasksAndInvalidate`方法将任务`invalidate`。

```objectivec
[[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(willTerminateNotification)
                                                 name:UIApplicationWillTerminateNotification
                                               object:nil];
                                               
- (void)willTerminateNotification {
    [self.session getAllTasksWithCompletionHandler:^(NSArray<__kindof NSURLSessionTask *> * _Nonnull tasks) {
        if (tasks.count) {
            [self.session finishTasksAndInvalidate];
        }
    }];
}
```