---
title: Core Animation(一) - UIView与CALayer、布局与绘制
date: 2021-09-07 14:50:38
urlname: core-animation01.html
tags:
categories:
  - 图形处理与渲染
---

Core Animation其实是一个令人误解的命名。你可能认为它只是用来做动画的，但实际上它是从一个叫做*Layer Kit*这么一个不怎么和动画有关的名字演变而来。

Core Animation是一个*复合引擎*，它的职责就是尽可能快地组合屏幕上不同的可视内容，这个内容是被分解成独立的*图层*，存储在一个叫做**图层树**的体系之中。于是这个树形成了**UIKit**以及在iOS应用程序当中你所能在屏幕上看见的一切的基础。

# 一、View与Layer

## 1.1 CALayer图层

> CALayer： 管理基于图像的内容，并允许你对该内容执行动画

在 iOS 中，所有的 view 都是由一个底层的 layer 来驱动的。view 和它的 layer 之间有着紧密的联系：

- view 其实直接从 layer 对象中获取了绝大多数它所需要的数据。
- layer给view提供了基础设施，使得绘制内容和呈现更高效动画更容易、更低耗；layer不参与view的事件处理、不参与响应链。

<img src="/images/caa/7.5.png" alt="" style="zoom:100%;" />

UIKit 中的每个视图都有自己的 CALayer 。 这个图层通常有一个缓存区/后备存储(Backing Store)，它是像素位图。这个后备存储实际上是渲染到显示器上的。

> 术语“后备存储”通常用于图形用户界面的上下文中。 是一块存储着窗口图像的内存块。如果窗口被覆盖（甚至部分覆盖）然后被发现，则后备存储用于重绘。

> 测试：分别修改、打印MyView与.layer的backgroundColor，可以看到这两者是同步变化的。**所以其实UIView的背景色就是CALayer的背景色。**

为什么iOS要基于`UIView`和`CALayer`提供两个平行的层级关系呢？为什么不用一个简单的层级来处理所有事情呢？原因在于要做职责分离，这样也能避免很多重复代码。

- 在iOS和Mac OS两个平台上，事件和用户交互有很多地方的不同，基于多点触控的用户界面和基于鼠标键盘有着本质的区别，这就是为什么iOS有UIKit和`UIView`，但是Mac OS有AppKit和`NSView`的原因。他们功能上很相似，但是在实现上有着显著的区别。
- 绘图，布局和动画，相比之下就是类似Mac笔记本和桌面系列一样应用于iPhone和iPad触屏的概念。把这种功能的逻辑分开并应用到独立的Core Animation框架，苹果就能够在iOS和Mac OS之间共享代码，使得对苹果自己的OS开发团队和第三方开发者去开发两个平台的应用更加便捷。

## 1.2 四个层级关系

在整个Core Animation机制中，存在4个层级关系：

### 1.2.1 视图层级

视图在层级关系中可以互相嵌套，一个视图可以管理它的所有子视图的位置。

### 1.2.2 图层树

每一个`UIView`都有一个`CALayer`实例的图层属性，也就是所谓的*backing layer*，视图的职责就是创建并管理这个图层，以确保当子视图在层级关系中添加或者被移除的时候，他们关联的图层也同样对应在层级关系树当中有相同的操作

### 1.2.3 呈现树

在iOS中，屏幕每秒钟重绘60次。如果动画时长比60分之一秒要长，Core Animation就需要在设置一次新值和新值生效之间，对屏幕上的图层进行重新组织。这意味着`CALayer`除了“真实”值（就是你设置的值）之外，必须要知道当前*显示*在屏幕上的属性值的记录。

每个图层属性的显示值都被存储在一个叫做*呈现图层*的独立图层当中，他可以通过`-presentationLayer`方法来访问。这个呈现图层实际上是模型图层（上面的图层树？）的复制，但是它的属性值代表了在任何指定时刻当前外观效果。换句话说，你可以通过呈现图层的值来获取当前屏幕上真正显示出来的值。

呈现树通过图层树中所有图层的呈现图层所形成。注意呈现图层仅仅当图层首次被*提交*（就是首次第一次在屏幕上显示）的时候创建，所以在那之前调用`-presentationLayer`将会返回`nil`。

### 1.2.4 渲染树

详见[下下篇 iOS渲染流程探究](https://tenloy.github.io/2021/09/11/core-animation03.html)

图层树的改动会在Application这一层以事务的形式完成打包提交，一旦打包的图层和动画到达渲染服务进程，他们会被反序列化来形成另一个叫做*渲染树*的图层树。使用这个树状结构，渲染服务对动画的每一帧做出如下工作：

- 对所有的图层属性计算中间值，设置OpenGL几何形状（纹理化的三角形）来执行渲染
- 在屏幕上渲染可见的三角形

# 二、View的绘制

> 苹果文档 —— [The View Drawing Cycle](https://developer.apple.com/library/archive/documentation/WindowsViews/Conceptual/ViewPG_iPhoneOS/WindowsandViews/WindowsandViews.html)

## 2.1 绘制机制

UIView 类使用按需绘制模型来呈现内容。

- 当一个视图第一次出现在屏幕上时，系统要求它绘制它的内容。系统捕获此内容的快照并将该快照用作视图的视觉表示。
- 如果您从不更改视图的内容，则视图的绘制代码可能永远不会被再次调用。大多数涉及视图的操作都会重复使用快照图像。
- 如果您确实更改了内容，则会通知系统视图已更改。然后视图重复绘制视图和捕获新结果的快照的过程。

当视图的内容发生更改时，不要直接重绘这些更改。可以使用 setNeedsDisplay 或 setNeedsDisplayInRect: 方法使视图无效。这些方法告诉系统视图的内容发生了变化，需要在下一次重绘。

## 2.2 绘制周期(当前runloop结束)

**系统会等到当前 run loop 执行结束(一个loop也就是一个绘制周期)，才启动任何绘图操作**。这种延迟使您有机会一次性使多个视图无效、在层次结构中添加或删除视图、隐藏视图、调整视图大小和重新定位视图。然后，所做的所有更改都会同时反映出来。苹果通过这种高性能的机制保障了视图渲染的流畅性（毕竟渲染比较消耗性能）。

> 参考链接 — [[译] 揭秘 iOS 布局](https://sq.sf.163.com/blog/article/200743376636538880)

Update cycle 是当应用完成了你的所有事件处理代码后控制流回到主 RunLoop 时的那个时间点。正是在这个时间点上系统开始更新布局、显示和设置约束。如果你在处理事件的代码中请求修改了一个 view，那么系统就会把这个 view 标记为需要重画（redraw）。在接下来的 Update cycle 中，系统就会执行这些 view 上的更改。

用户交互和布局更新间的延迟几乎不会被用户察觉到。iOS 应用一般以 60 fps 的速度展示动画，就是说每个更新周期只需要 1/60 秒。这个更新的过程很快，所以用户在和应用交互时感觉不到 UI 中的更新延迟。

但是由于在处理事件和对应 view 重画间存在着一个间隔，RunLoop 中的某时刻的 view 更新可能不是你想要的那样。如果你的代码中的某些计算依赖于当下的 view 内容或者是布局，那么就有在过时 view 信息上操作的风险。

理解 RunLoop、update cycle 和 `UIView` 中具体的方法可以帮助避免或者可以调试这类问题。

下面的图展示出了 update cycle 发生在 RunLoop 的尾部。

<img src="/images/caa/updatecycle.jpg" alt="updatecycle" style="zoom:75%;" />

*可以通过监听RunLoop的状态、layoutSubviews的调用情况验证*：

```
2022-02-24 17:05:55.552069 ================休眠中================
2022-02-24 17:05:55.624499 kCFRunLoopAfterWaiting
2022-02-24 17:05:55.624638 kCFRunLoopBeforeTimers
2022-02-24 17:05:55.624754 kCFRunLoopBeforeSources
2022-02-24 17:05:55.626445 kCFRunLoopBeforeWaiting
2022-02-24 17:05:55.627835 layoutSubviews调用
```

<img src="/images/caa/layoutSubviews.png" style="zoom:90%;" />

从上图中可以看到：

- `runloop`的`observer`回调 
- => `CoreAnimation`渲染引擎一次事务的提交 
- => `CoreAnimation`递归查询图层是否有布局上的更新
- => `CALayer` `layoutSublayers`
- => `UIView` `layoutSubviews` 这样一个调用的流程。

从这里也可以看到`UIView`其实就是相当于`CALayer`的代理。

<img src="/images/caa/drawRect.png" style="zoom:90%;" />

顺便看一眼`drawRect`方法的调用栈，从`CA::Layer::layout_and_display_if_needed`方法之前都是一样的。

## 2.3 Custom Drawing

> 寄宿图：CALayer类除了简单的设置背景颜色外，还能够包含一张图片。又称CALayer的寄宿图（即图层中包含的图）。

当需要渲染视图的内容时，实际的绘制过程取决于视图及其配置。系统视图通常实现私有绘图方法来呈现其内容。这些相同的系统视图经常公开接口，您可以使用这些接口来配置视图的实际外观。

- 直接设置layer的contents属性
- 对于自定义 UIView 子类，可以重写 drawRect: 方法并使用该方法绘制视图的内容。（最常用）

### 2.3.1 contents属性

CALayer 有一个属性叫做`contents`，这个属性的类型被定义为id，意味着它可以是任何类型的对象。在这种情况下，你可以给`contents`属性赋任何值，你的app都能够编译通过。但是，在实践中，如果你给`contents`赋的不是CGImage，那么你得到的图层将是空白的。

`contents`这个奇怪的表现是由Mac OS的历史原因造成的。它之所以被定义为id类型，是因为在Mac OS系统上，这个属性对CGImage和NSImage类型的值都起作用。如果你试图在iOS平台上将UIImage的值赋给它，只能得到一个空白的图层。一些初识Core Animation的iOS开发者可能会对这个感到困惑。

头疼的不仅仅是我们刚才提到的这个问题。事实上，你真正要赋值的类型应该是CGImageRef，它是一个指向CGImage结构的指针。UIImage有一个CGImage属性，它返回一个"CGImageRef"，如果你想把这个值直接赋值给CALayer的`contents`，那你将会得到一个编译错误。因为CGImageRef并不是一个真正的Cocoa对象，而是一个Core Foundation类型。

尽管Core Foundation类型跟Cocoa对象在运行时貌似很像（被称作toll-free bridging），它们并不是类型兼容的，不过你可以通过bridged关键字转换。如果要给图层的寄宿图赋值，你可以按照以下这个方法：

```
layer.contents = (__bridge id)image.CGImage;
```

如果你没有使用ARC（自动引用计数），你就不需要__bridge这部分。但是，你干嘛不用ARC？！

### 2.3.2 drawRect

`-drawRect:` 方法没有默认的实现，因为对UIView来说，寄宿图并不是必须的，它不在意那到底是单调的颜色还是有一个图片的实例。如果UIView检测到`-drawRect:` 方法被调用了，它就会为视图分配一个寄宿图，这个寄宿图的像素尺寸等于视图大小乘以 `contentsScale`的值。

如果你不需要寄宿图，那就不要创建这个方法了，这会造成CPU资源和内存的浪费，这也是为什么苹果建议：**如果没有自定义绘制的任务就不要在子类中写一个空的-drawRect:方法**。

当视图在屏幕上出现的时候 `-drawRect:`方法就会被自动调用。`-drawRect:`方法里面的代码利用Core Graphics去绘制一个寄宿图，然后**内容就会被缓存起来直到它需要被更新**（比如手动调用了`-setNeedsDisplay`方法。当影响到表现效果的属性值被更改时，一些视图类型会被自动重绘，如`bounds`属性）。虽然`-drawRect:`方法是一个UIView方法，事实上都是底层的CALayer安排了重绘工作和保存了因此产生的图片。

CALayer有一个可选的`delegate`属性，实现了`CALayerDelegate`协议，当CALayer需要一个内容特定的信息时，就会从协议中请求。CALayerDelegate是一个非正式协议，其实就是说没有CALayerDelegate @protocol可以让你在类里面引用啦。你只需要调用你想调用的方法，CALayer会帮你做剩下的。（`delegate`属性被声明为id类型，所有的代理方法都是可选的）。

当需要被重绘时，CALayer会请求它的代理给它一个寄宿图来显示。它通过调用下面这个方法做到的:

```objectivec
(void)displayLayer:(CALayer *)layer;
```

趁着这个机会，如果代理想直接设置`contents`属性的话，它就可以这么做，不然没有别的方法可以调用了。如果代理不实现`-displayLayer:`方法，CALayer就会转而尝试调用下面这个方法：

```objectivec
- (void)drawLayer:(CALayer *)layer inContext:(CGContextRef)ctx;
```

在调用这个方法之前，CALayer创建了一个合适尺寸的空寄宿图（尺寸由`bounds`和`contentsScale`决定）和一个Core Graphics的绘制上下文环境，为绘制寄宿图做准备，它作为ctx参数传入。

现在你理解了CALayerDelegate，并知道怎么使用它。但是除非你创建了一个单独的图层，你几乎没有机会用到CALayerDelegate协议。因为当UIView创建了它的宿主图层时，它就会自动地把图层的delegate设置为它自己，并提供了一个`-displayLayer:`的实现，那所有的问题就都没了。

当使用寄宿了视图的图层的时候，你也不必实现`-displayLayer:`和`-drawLayer:inContext:`方法来绘制你的寄宿图。通常做法是实现UIView的`-drawRect:`方法，UIView就会帮你做完剩下的工作，包括在需要重绘的时候调用`-display`方法。

# 三、布局-绘制流程

## 3.1 绘制/显示流程图

写在前面：注意：**更改视图的几何形状不会自动导致系统重绘视图的内容**。视图的内容模式(contentMode)属性决定了如何解释视图几何的变化。大多数content modes会在视图边界内拉伸或重新定位现有快照，并且不会创建新快照。有关内容模式如何影响视图的绘制周期的更多信息，请参阅[Content Modes](https://developer.apple.com/library/archive/documentation/WindowsViews/Conceptual/ViewPG_iPhoneOS/WindowsandViews/WindowsandViews.html)。

先来看一下**更新-绘制流程图**，然后梳理一下其中的重要方法

<img src="/images/caa/viewdraw.png" alt="viewredraw" style="zoom:80%;" />

- 当我们调用 `[UIView setNeedsDisplay]` 这个方法时，其实并没有立即进行绘制工作，系统会立刻调用CALayer的同名方法，并且**会在当前layer上打上一个标记，然后会在当前runloop将要结束的时候（下一个绘制周期）**调用 `[CALayer display]` 这个方法，然后进入我们视图的真正绘制过程。
- 无论是哪个分支，**最终都会由CALayer上传对应的backing store(寄宿图，也即位图bitmap)给GPU**。

## 3.2 异步绘制

因为UIKit不是线程安全的，所以官方建议我们只在主线程操作。那么就无法利用cpu多核的优势，当大量且频繁的绘制任务，以及各种业务逻辑同时放在主线程上完成时，便有可能造成界面卡顿，丢帧现象。

但通过对UIView绘制原理的了解我们知道，异步绘制是有理论基础的。

异步绘制的原理：我们不能在非主线程将内容绘制到layer的context上，但是我们可以将需要绘制的内容绘制在一个自己创建的跑private_context上。通过`CGBitmapContextCreate()`可以创建一个`CGCentextRef`，在异步线程使用这个context进行绘制，最后通过`CGBitmapContextCreateImage()`创建一个`CGImageRef`，并在主线程设置给layer的contents，完成异步绘制。

```objc
- (void)display {
    // 由于 CoreGraphic 方法通常都是线程安全的，所以图像的绘制可以很容易的放到后台线程进行。
    dispatch_async(backgroundQueue, ^{
        CGContextRef ctx = CGBitmapContextCreate(...);
        // draw in context...
        CGImageRef img = CGBitmapContextCreateImage(ctx);
        CFRelease(ctx);
        dispatch_async(mainQueue, ^{
            layer.contents = img;
        });
    });
}
```

所以，异步绘制/渲染就是在子线程进行绘制，然后拿到主线程显示。

<img src="/images/caa/viewdrawasync.png" alt="viewdrawasync" style="zoom:70%;" />

参考链接：[iOS 保持界面流畅的技巧 - ibireme](https://blog.ibireme.com/2015/11/12/smooth_user_interfaces_for_ios/)、[YYKit异步渲染的基础 — YYAsyncLayer](https://github.com/ibireme/YYAsyncLayer/tree/master/YYAsyncLayer)

## 3.3 布局计算 — layoutSubxxxs

一个视图的布局指的是它在屏幕上的的大小和位置。每个 view 都有一个 frame 属性，用来表示在父 view 坐标系中的位置和具体的大小。

`UIView` 给你提供了用来通知系统某个 view 布局发生变化的方法(*setNeedsLayout*)。也提供了在 view 布局重新计算(*layoutSubviews*)后调用的可重写的方法(*viewDidLayoutSubviews*)。

### 3.3.1 UIView方法

#### 1. -layoutSubviews

##### 1) 概述

默认实现中，会使用你设置的任何约束，来**确定每一个子视图的位置和大小**。

这个 `UIView` 方法处理对所有子视图（subview）的重新定位和大小调整。这个方法很开销很大，因为它会在每个子视图上起作用并且调用它们相应的 `layoutSubviews` 方法。

使用场景：

- **子类可以根据需要重写此方法，以对其子视图执行更精确的布局**。 仅当子视图的自动调整大小和基于约束的行为不提供您想要的行为时，你才应该重写此方法，可以在实现中直接设置子视图的frame。
- **通俗地说：当我们在某个类的内部调整子视图位置时，需要调用。反之，如果你想要在外部设置subviews的位置，就不要重写。**
  ```objc
  - (void)layoutSubviews {
      [super layoutSubviews];
      self.datePicker.frame = self.bounds;
  }
  ```

系统会在任何它需要重新计算视图的 frame 的时候调用这个方法，然而你**不应直接调用**此方法。 如果要强制更新布局，请在下一次绘图更新之前调用 setNeedsLayout 方法。 如果您想立即更新视图的布局，请调用 layoutIfNeeded 方法。

##### 2) layoutSubviews的自动触发

**layoutSubViews的自动触发 — 本轮RunLoop结束前调用layoutSubViews。**有许多可以在 RunLoop 的不同时间点触发 `layoutSubviews` 调用的机制，这些触发机制比直接调用 `layoutSubviews` 的资源消耗要小得多。

**更新布局总会重新触发`layoutSubviews`方法**。有许多事件会**自动给视图打上 “update layout” 标记**，因此 `layoutSubviews` 会在下一个周期中被调用，而不需要开发者手动操作。这些自动通知系统 view 的布局发生变化的方式有：

- 修改 view 的大小
  - 设置/修改view的frame.size、bounds.size、bounds.origin都会触发superView和自己view的layoutSubviews方法(父类在前)。
  - 当然前提是设置前后值发生了变化。修改frame.origin不会触发。
- 新增 subview
- 用户在 `UIScrollView` 上滚动（`layoutSubviews`会在`UIScrollView`和它的父 view 上被调用）
- 用户旋转设备
- 更新视图的 constraints

注意：

- init初始化不会触发layoutSubviews（view 的创建并不被标记为需要刷新的，只有设置了一个不为CGRectZero的frame才会触发。可能初始化时view的frame默认被系统设置CGRectZero吧 ）。
- view必须得显示，才会调用layoutSubviews。否则，假如创建了，但最后没有被addSubview，那是不会调用的。

上面的方式都会告知系统 view 的位置需要被重新计算，继而会自动转化为一个最终的 `layoutSubviews` 调用。当然，也有直接触发 `layoutSubviews` 的方法。

##### 3) layoutSubviews的手动触发

**setNeedsLayout手动标记 — 本轮RunLoop结束前调用layoutSubviews。**

- 标记为需要重新布局。调用这个方法代表向系统表示视图的布局需要重新计算。
- `setNeedsLayout` 方法会立刻执行并返回，但在返回前不会真正更新视图。视图会在下一个update cycle(*本轮runloop结束前*)中通过调用视图们以及他们的所有子视图的 `layoutSubviews` 来更新。对于这一轮`runloop`之内的所有布局和UI上的更新只会刷新一次。
- 即从 `setNeedsLayout` 返回后到视图被重新绘制并布局之间有一段任意时间的间隔，但是这个延迟不会对用户造成影响，因为永远不会长到对界面造成卡顿。
- **`layoutSubviews`一定会被调用（有延迟，在下一个update cycle）**。

**layoutIfNeeded — 不一定会调用，若满足条件，则立即调用layoutSubviews。**

- 如果有需要刷新的标记，立即调用`layoutSubviews`进行布局。如果没有标记，不会调用`layoutSubviews`。即**不一定会调用layoutSubviews方法**。
- 使用 `layoutIfNeeded`，则布局和重绘会立即发生并在函数返回之前完成（除非有正在运行中的动画）。
- 这个方法在你需要依赖新布局，无法等到下一次 update cycle 的时候会比 `setNeedsLayout` 有用。除非是这种情况，否则你更应该使用 `setNeedsLayout`，这样在每次 run loop 中都只会更新一次布局。
- 当对希望通过修改 constraint 进行动画时，这个方法特别有用。你需要在 animation block 之前对 self.view 调用 `layoutIfNeeded`，以确保在动画开始之前传播所有的布局更新。在 animation block 中设置新 constrait 后，需要再次调用 `layoutIfNeeded` 来动画到新的状态。

如果想在当前`runloop`中立即刷新，调用顺序应该是

```objc
[self setNeedsLayout];
[self layoutIfNeeded];
// 注意：修改了当前视图的size(origin不算)，默认会被系统标记setNeedsLayout的，所以有时候会出现，没有调用setNeedsLayout标记，直接调用layoutIfNeeded，也触发了layoutSubviews调用。
```

反之可能会出现布局错误的问题。

##### 4) viewDidLayoutSubviews

当 `layoutSubviews` 完成后，在 view 的所有者 view controller 上，会触发 `viewDidLayoutSubviews` 调用。因为 `viewDidLayoutSubviews` 是 view 布局更新后会被唯一可靠调用的方法，所以你应该把所有依赖于布局或者大小的代码放在 `viewDidLayoutSubviews` 中，而不是放在 `viewDidLoad` 或者 `viewDidAppear` 中。这是避免使用过时的布局或者位置变量的唯一方法。

#### 2. -setNeedsLayout(做标记)

使当前布局无效并在下一个更新周期触发布局更新。

当您想要调整视图子视图的布局时，请**在应用程序的主线程上调用此方法**。此方法记录请求并立即返回。

由于此方法不会强制立即更新，而是等待下一个更新周期，因此您可以使用它在更新任何视图之前使多个视图的布局无效。此行为**允许您将所有布局更新合并到一个更新周期，这通常对性能更好**。

#### 3. -layoutIfNeeded(立即)

如果有待办的(pending)布局更新，则立即布局子视图。

使用此方法强制视图立即更新其布局。使用“自动布局”时，布局引擎会根据需要更新视图的位置，以满足约束的更改。用接收此消息的视图作为根视图开始布局视图子树。

如果没有待处理的布局更新，则此方法退出而不修改布局或调用任何与布局相关的回调。

### 3.3.2 CALayer方法

#### 1. -layoutSublayers

告诉图层更新其布局 

子类可以覆盖此方法并使用它来实现自己的布局算法。您的实现必须设置每个子层的frame。

此方法的默认实现：

- 如果 layer 有delegate对象，且实现了 layoutSublayersOfLayer: 方法，调用它。
- 否则，该方法调用 layoutManager 属性对象(Mac OS API)的 layoutSublayersOfLayer: 方法。 

#### 2. -setNeedsLayout(做标记)

使图层的布局无效并将其标记为需要更新。会在下一个更新周期中触发布局更新。系统调用任何需要布局更新的图层的 layoutSublayers 方法。

当图层的边界发生变化或添加或删除子图层时，系统通常会自动调用此方法。   

#### 3. -layoutIfNeeded(立即)

 如果需要，立即重新计算图层的布局。

 收到此消息后，将遍历该图层的父图层，直到找到不需要布局的祖先图层。然后在该祖先下的整个层树上执行布局。

## 3.4 内容绘制 — draw | display

一个视图的显示包含了颜色、文本、图片和 Core Graphics 绘制等视图属性，不包括其本身和子视图的大小和位置。和<font color='red'>布局</font>的方法类似，<font color='red'>显示</font>也有触发更新的方法，它们由系统在检测到更新时被自动调用，或者我们可以手动调用直接刷新。

### 3.4.1 UIView方法 (UIViewRendering分类)

#### 1. drawRect:

##### 1) 概述

在传入的矩形内绘制接收者的图像。此方法的默认实现不执行任何操作。 

- 如果你要使用 Core Graphics 和 UIKit 等技术来绘制视图内容，那么该子类应该重写此方法并在那里实现其绘制代码。
- 如果你的视图仅显示背景颜色或者直接使用底层的对象填充其内容，则无需重写此方法。

当这个方法被调用时，UIKit 已经为你的视图配置了合适的绘图环境，你可以简单地调用任何你需要的绘图方法和函数来渲染你的内容。具体来说，UIKit 创建和配置一个用于绘制的图形上下文，并调整该上下文的变换，使其原点与视图边界矩形的原点相匹配。您可以使用 UIGraphicsGetCurrentContext 函数获取对图形上下文的引用，但不要建立对图形上下文的强引用，因为它可以在对 drawRect: 方法的调用之间发生变化。

当第一次显示视图或发生使视图的可见部分无效的事件时，将调用此方法。你永远不应该自己直接调用这个方法。要使视图的一部分无效，从而导致该部分被重绘，请调用 setNeedsDisplay 或 setNeedsDisplayInRect: 方法。

```objc
- (void)drawRect:(CGRect)rect;
```

`UIView` 的 `drawRect`方法对视图内容显示的操作，类似于视图布局的 `layoutSubviews` ，但是不同于 `layoutSubviews`，`drawRect` 方法不会触发后续对视图的子视图方法的调用。同样，和 `layoutSubviews` 一样，你不应该直接调用 `drawRect` 方法，而应该通过调用触发方法，让系统在 run loop 中的不同结点自动调用。

##### 2) 自动触发

在以下情况下会被调用：

1. 如果在UIView初始化时没有设置rect大小，将直接导致drawRect不被自动调用。drawRect 调用是在Controller->loadView, Controller->viewDidLoad 两方法之后调用的。所以不用担心在控制器中，这些View的drawRect就开始画了。这样可以在控制器中设置一些值给View(如果这些View draw的时候需要用到某些变量值)。
2. 该方法在调用sizeToFit后被调用，所以可以先调用sizeToFit计算出size。然后系统自动调用drawRect:方法。
3. 通过设置contentMode属性值为UIViewContentModeRedraw。那么将在每次设置或更改frame的时候自动调用drawRect:。
4. 直接调用setNeedsDisplay，或者setNeedsDisplayInRect:触发drawRect:，但是有个前提条件是rect不能为0。

**以上1,2推荐；而3,4不提倡。**

drawRect方法使用注意点：

1. 若使用UIView绘图，只能在drawRect: 方法中获取相应的contextRef并绘图。如果在其他方法中获取将获取到一个invalidate 的ref并且不能用于画图。
2. drawRect：方法不能手动显示调用，必须通过调用setNeedsDisplay 或 者 setNeedsDisplayInRect，让系统自动调该方法。
3. 若使用calayer绘图，只能在drawInContext: 中（类似于drawRect）绘制，或者在delegate中的相应方法绘制。同样也是调用setNeedDisplay等间接调用以上方法。
4. 若要实时画图，不能使用gestureRecognizer，只能使用touchbegan等方法来调用setNeedsDisplay实时刷新屏幕。

#### 2. -setNeedsDisplay

通知系统你的视图内容需要重绘。此方法将指定的矩形添加到视图的当前无效矩形列表中并立即返回。直到下一个绘制周期才会真正重绘视图，此时所有无效的视图都会更新。

你应该仅在视图的内容或外观发生更改时，使用此方法请求重绘视图。**如果只是更改视图的几何形状，通常不会重新绘制视图，它的现有内容根据视图的 contentMode 属性中的值进行调整。**

 注意：如果您的视图由 CAEAGLLayer 对象支持，则此方法无效。它仅适用于使用原生绘图技术（例如 UIKit 和 Core Graphics）来呈现其内容的视图。

```objectivec
// 重绘范围是整个边界矩形
- (void)setNeedsDisplay;
// 重绘范围是参数指定的矩形(应在接收器的坐标系中指定, 且只对该图层有效)
- (void)setNeedsDisplayInRect:(CGRect)rect;
```

这个方法类似于布局中的 `setNeedsLayout` 。它会给有内容更新的视图设置一个内部的标记，但在视图重绘之前就会返回。然后在下一个 update cycle 中，系统会遍历所有已标标记的视图，并调用它们的 `draw` 方法。

如果你只想在下次更新时重绘部分视图，你可以调用 `setNeedsDisplay(_:)`，并把需要重绘的矩形部分传进去（`setNeedsDisplayInRect` in OC)。

大部分时候，在视图中更新任何 UI 组件都会把相应的视图标记为“**dirty**”，通过设置视图“内部更新标记”，在下一次 update cycle 中就会重绘，而**不需要显式的 `setNeedsDisplay` 调用**。然而**如果你有一个属性没有绑定到 UI 组件，但需要在每次更新时重绘视图**，你可以定义他的 `didSet` 属性，并且调用 `setNeedsDisplay` 来触发视图合适的更新。

> 脏数据依据不同的分析目的有不同的定义：
>
> - 从广义上看，脏数据是指没有进行过数据预处理而直接接收到的、处于原始状态的数据；从狭义上看，是不符合研究要求，以及不能够对其直接进行相应的数据分析。在常见的数据挖掘工作中，脏数据是指不完整、含噪声、不一致的数据；在问卷分析中，脏数据则是指不符合问卷要求的数据。
> - 在一些编程场景中，脏数据可以看做是发生了改变的数据(Git中有些场合中，将有改动未commit的状态称为dirty，都commit了称为clean)

有时候设置一个属性要求自定义绘制，这种情况下你需要重写 `drawRect` 方法。在下面的例子中，设置 `numberOfPoints` 会触发系统系统根据具体点数绘制视图。在这个例子中，你需要在 `drawRect` 方法中实现自定义绘制，并在 `numberOfPoints` 的 property observer 里调用 `setNeedsDisplay`。

```swift
class MyView: UIView {
    var numberOfPoints = 0 {
        didSet {
            setNeedsDisplay()
        }
    }
    override func draw(_ rect: CGRect) {
        switch numberOfPoints {
        case 0:
            return
        case 1:
            drawPoint(rect)
        case 2:
            drawLine(rect)
        case 3:
            drawTriangle(rect)
        case 4:
            drawRectangle(rect)
        case 5:
            drawPentagon(rect)
        default:
            drawEllipse(rect)
        }
    }
}
```

视图的显示方法里没有类似布局中的 `layoutIfNeeded` 这样可以触发立即更新的方法。通常情况下等到下一个更新周期再重新绘制视图也无所谓。

### 3.4.2 CALayer方法

#### 1. -display

> Reload the content of this layer. 调用-drawInContext:方法，然后更新layer的'contents'属性。

通常不要直接调用此方法。图层在适当的时候调用这个方法来更新图层的内容。

- 如果layer有一个delegate对象，且实现了 displayLayer: 方法，那么就调用该方法来更新 layer 的内容。
- 如果委托未实现 displayLayer: 方法，则此方法创建一个后备存储(Backing Store)并调用该layer的 drawInContext:方法以用内容填充该后备存储。新的后备存储替换了layer的先前contents。

#### 2. -drawInContext:

```objectivec
/*
 * 使用指定的图形上下文绘制图层的内容。
 * @param ctx 在其中绘制内容的图形上下文。可以剪裁上下文以保护有效的层内容。
 * 						希望找到要绘制的实际区域的子类可以调用 CGContextGetClipBoundingBox。
 */
- (void)drawInContext:(CGContextRef)ctx;
```

此方法的默认实现本身不进行任何绘图。 如果图层的委托实现了 drawLayer:inContext: 方法，则调用该方法来进行实际绘制。

子类可以覆盖此方法并使用它来绘制图层的内容。 绘制时，所有坐标都应在逻辑坐标空间中以点为单位指定。

#### 3. -setNeedsDisplay

将图层的内容标记为需要更新。

调用此方法会导致图层重新缓存其内容。 这导致图层可能调用其委托的 displayLayer: 或 drawLayer:inContext: 方法。 删除图层 contents 属性中的现有内容，为新内容让路。

```objectivec
// 重绘范围是整个边界矩形
- (void)setNeedsDisplay;
// 重绘范围是参数指定的矩形(应在接收器的坐标系中指定, 且只对该图层有效)
- (void)setNeedsDisplayInRect:(CGRect)rect;
```

### 3.4.3 CALayerDelegate方法

```objectivec
@protocol CALayerDelegate <NSObject>
@optional
/* Tells the delegate to implement the display process(实现显示过程)
   如果实现了，则由layer的-display方法的默认实现调用，在这种情况下，它应该实现整个display过程(通常是通过设置'contents'属性)。*/
- (void)displayLayer:(CALayer *)layer;

/* Tells the delegate to implement the display process using the layer's CGContextRef.
   This method is not called if the delegate implements displayLayer:
   如果定义了，则由layer的-drawInContext的默认实现调用 */
- (void)drawLayer:(CALayer *)layer inContext:(CGContextRef)ctx;

/* 如果定义了，则由layer的-display方法的默认实现调用。
	 允许delegate在-drawLayer:InContext之前配置任何影响内容的图层状态，如'contentsFormat'和' opaque'。如果委托实现了-displayLayer，它将不会被调用。*/
- (void)layerWillDraw:(CALayer *)layer
  API_AVAILABLE(macos(10.12), ios(10.0), watchos(3.0), tvos(10.0));

/* 如果实现了，则由layer的-layoutSublayers方法的默认实现调用(在检查layoutManager之前)。
   注意，如果调用委托方法，布局管理器将被忽略。*/
- (void)layoutSublayersOfLayer:(CALayer *)layer;

/* 隐式动画中用到的 */
- (nullable id<CAAction>)actionForLayer:(CALayer *)layer forKey:(NSString *)event;
@end
```

# 四、自动布局

自动布局包含三步来布局和重绘视图。

- 第一步是更新约束，系统会计算并给视图设置所有要求的约束。
- 第二步是布局阶段，布局引擎计算视图和子视图的 frame 并且将它们布局。
- 最后一步完成这一循环的是显示阶段，重绘视图的内容，如实现了 `draw` 方法则调用 `draw`。

## 4.1 约束更新的几个方法

```objc
@interface UIView (UIConstraintBasedLayoutCoreMethods) 
```

### 4.1.1 updateConstraints()

这个方法用来在自动布局中动态改变视图约束。和布局中的 `layoutSubviews()` 方法或者显示中的 `draw` 方法类似，`updateConstraints()` 只应该被重载，绝不要在代码中显式地调用。通常你只应该在 `updateConstraints` 方法中实现必须要更新的约束。静态的约束应该在 interface builder、视图的初始化方法或者 `viewDidLoad()` 方法中指定。

通常情况下，设置或者解除约束、更改约束的优先级或者常量值，或者从视图层级中移除一个视图时都会设置一个内部的标记 “update constarints”，这个标记会在下一个更新周期中触发调用 `updateConstrains`。当然，也有手动给视图打上“update constarints” 标记的方法，如下。

### 4.1.2 setNeedsUpdateConstraints()

调用 `setNeedsUpdateConstraints()` 会保证在下一次更新周期中更新约束。它通过标记“update constraints”来触发 `updateConstraints()`。这个方法和 `setNeedsDisplay()` 以及 `setNeedsLayout()` 方法的工作机制类似。

### 4.1.3 updateConstraintsIfNeeded()

对于使用自动布局的视图来说，这个方法与 `layoutIfNeeded` 等价。它会检查 “update constraints”标记（可以被 `setNeedsUpdateConstraints` 或者 `invalidateInstrinsicContentSize`方法自动设置）。如果它认为这些约束需要被更新，它会立即触发 `updateConstraints()` ，而不会等到 run loop 的末尾。

### 4.1.4 invalidateIntrinsicContentSize()

自动布局中某些视图拥有 `intrinsicContentSize` 属性，这是视图根据它的内容得到的自然尺寸。一个视图的 `intrinsicContentSize` 通常由所包含的元素的约束决定，但也可以通过重载提供自定义行为。调用 `invalidateIntrinsicContentSize()` 会设置一个标记表示这个视图的 `intrinsicContentSize` 已经过期，需要在下一个布局阶段重新计算。

## 4.2 约束—布局—显示的流程

布局、显示和约束都遵循着相似的模式，例如他们更新的方式以及如何在 run loop 的不同时间点上强制更新。任一组件都有一个实际去更新的方法（`layoutSubviews`, `drawRect`, 和 `updateConstraints`），你可以重写来手动操作视图，但是任何情况下都不要显式调用。这个方法只在 run loop 的末端会被调用，如果视图被标记了告诉系统该视图需要被更新的标记的话。

**有一些操作会自动设置这个标志**，但是也有一些方法允许您显式地设置它。对于布局和约束相关的更新，如果你等不到在 run loop 末端才更新（例如：其他行为依赖于新布局），有方法可以让你**立即更新，并保证 “update layout” 标记被正确标记**。下面的表格列出了任意组件会怎样更新及其对应方法。

下面的流程图总结了 update cycle 和 event loop 之间的交互，并指出了上文提到的方法在 run loop 运行期间的位置。

<img src="/images/caa/layoutdraw.png" alt="layoutdraw" style="zoom:70%;" />

你可以在 run loop 中的任意一点显式地调用 layoutIfNeeded 或者 updateConstraintsIfNeeded，需要记住，这开销会很大。在循环的末端是 update cycle，如果视图被设置了特定的 “update constraints”，“update layout” 或者 “needs display” 标记，在这节点会更新约束、布局以及展示。一旦这些更新结束，runloop 会重新启动。

<img src="/images/caa/layoutdraw2.png" alt="layoutdraw2" style="zoom:90%;" />

## 4.3 约束的实现原理

Auto Layout 不只有布局算法 Cassowary，还包含了布局在运行时的生命周期等一整套布局引擎系统，用来统一管理布局的创建、更新和销毁。了解 Auto Layout 的生命周期，是理解它的性能相关话题的基础。这样，在遇到问题，特别是性能问题时，我们才能从根儿上找到原因，从而避免或改进类似的问题。

这一整套布局引擎系统叫作 Layout Engine ，是 Auto Layout 的核心，主导着整个界面布局。

每个视图在得到自己的布局之前，Layout Engine 会将视图、约束、优先级、固定大小通过计算转换成最终的大小和位置。在 Layout Engine 里，每当约束发生变化，就会触发 Deffered Layout Pass，完成后进入监听约束变化的状态。当再次监听到约束变化，即进入下一轮循环中。Layout Engine 界面布局过程如下图所示：

<img src="/images/caa/7ca0e14ef02231c9aba7cb49c7e9271c.webp" style="zoom:50%;" />

图中：

- Constraints Change 表示的就是约束变化，添加、删除视图时会触发约束变化。Activating 或 Deactivating，设置 Constant 或 Priority 时也会触发约束变化。
- Layout Engine 在碰到约束变化后会重新计算布局，获取到布局后调用 superview.setNeedLayout()，然后进入 Deferred Layout Pass。
- Deferred Layout Pass 的主要作用是做容错处理。如果有些视图在更新约束时没有确定或缺失布局声明的话，会先在这里做容错处理。
- 接下来，Layout Engine 会从上到下调用 layoutSubviews() ，通过 Cassowary 算法计算各个子视图的位置，算出来后将子视图的 frame 从 Layout Engine 里拷贝出来。
- 在这之后的处理，就和手写布局的绘制、渲染过程一样了。

所以，使用 Auto Layout 和手写布局的区别，就是多了布局上的这个计算过程。

## 4.4 自动布局的性能

iOS12之前：

- 如果兄弟视图间有关系的话，在视图遍历时会不断处理和兄弟视图间的关系，这时会有修改更新计算。此时，**视图嵌套的数量对性能的影响是呈指数级增长的**。
- 兄弟视图之间没有关系时，呈线性增长。这就表示 Cassowary 算法在添加时是高效的。

这个锅应该由 Cassowary 算法来背吗？

在 1997 年时，Cassowary 是以高效的界面线性方程求解算法被提出来的。它解决的是界面的线性规划问题，而线性规划问题的解法是 Simplex 算法。单从 Simplex 算法的复杂度来看，多数情况下是没有指数时间复杂度的。而 Cassowary 算法又是在 Simplex 算法基础上对界面关系方程进行了高效的添加、修改更新操作，不会带来时间复杂度呈指数级增长的问题。

那么，如果 Cassowary 算法本身没有问题的话，问题就只可能是苹果公司在 iOS 12 之前在某些情况下没有用好这个算法。

实际情况是，iOS 12 之前，很多约束变化时都会重新创建一个计算引擎 NSISEnginer 将约束关系重新加进来，然后重新计算。结果就是，涉及到的约束关系变多时，新的计算引擎需要重新计算，最终导致计算量呈指数级增加。

更详细的讲解，你可以参考 WWDC 2018 中 202 Session 的内容，里面完整地分析了以前的问题，以及 iOS12 的解法。

总体来说，**iOS12 的 Auto Layout 更多地利用了 Cassowary 算法的界面更新策略，使其真正完成了高效的界面线性策略计算。iOS 12使得 Auto Layout 具有了和手写布局几乎相同的高性能**，可以放心地使用 Auto Layout 了呢。

## 4.5 autolayout两个优先级

> 使用 Auto Layout 一定要注意多使用 Compression Resistance Priority 和 Hugging Priority，利用优先级的设置，让布局更加灵活，代码更少，更易于维护。

```objc
@interface UIView (UIConstraintBasedLayoutLayering)

/* 具有instrinsic content size的控件，比如UILabel，UIButton，选择控件，进度条和分段等等，可以根据设置的内容，来自己计算自己的大小，比如label设置text和font后大小是可以计算得到的。 
*/
@property(nonatomic, readonly) CGSize intrinsicContentSize API_AVAILABLE(ios(6.0));

// 属性对有intrinsic content size的控件（例如button，label）非常重要.

/* 抗拉伸优先级。
   用途：可以通过设置Hugging priority让这些控件不要大于某个设定的值。
   默认优先级为250。值越小，视图越容易被拉伸 */
- (void)setContentHuggingPriority:(UILayoutPriority)priority forAxis:(UILayoutConstraintAxis)axis API_AVAILABLE(ios(6.0));
/* 抗压缩优先级,
   用途：可以通过设置Content Compression Resistance就是让控件不要小于某个设定的值。
   默认优先级为750。值越小，视图越容易被压缩 */
- (void)setContentCompressionResistancePriority:(UILayoutPriority)priority forAxis:(UILayoutConstraintAxis)axis API_AVAILABLE(ios(6.0));
@end
```

使用场景：当父视图宽高已定，两个子控件label左右排列：

```c
左label约束:上0,左0,下0       //左侧与父控件左侧对齐
右label约束:上0,左0,下0,右0   //右侧与父控件右侧对齐。即两个子控件宽度充满父控件
```

都没设置宽度，宽度由label文字多少自己决定，此时你会发现：

- 当两个label的内容不能充满父控件宽度时：约束报错：

```c
labels Set horizontal hugging priority to 251/249. 
//意思是两个子控件，抗拉伸优先级不能一样，不能都是250，得有个高低，谁的低就去拉伸谁，以达到总宽度能拉伸到父控件宽度
```

- 当两个label的内容超出了父控件宽度时：约束报错：

```c
labels Set horizontal compression resistance priority to 751/749. 
//意思是两个子控件，抗压缩优先级不能一样，不能都是750，得有个高低，谁的低就去压缩谁，以达到总宽度能压缩到父控件宽度
```

设置：

- xib中，有右侧尺寸检查器中，有此选项
- 代码中：
  ```objc
  static const UILayoutPriority UILayoutPriorityRequired = 1000;
  static const UILayoutPriority UILayoutPriorityDefaultHigh = 750;
  static const UILayoutPriority UILayoutPriorityDragThatCanResizeScene = 510;
  static const UILayoutPriority UILayoutPrioritySceneSizeStayPut = 500;
  static const UILayoutPriority UILayoutPriorityDragThatCannotResizeScene = 490; 
  static const UILayoutPriority UILayoutPriorityDefaultLow = 250; 
  static const UILayoutPriority UILayoutPriorityFittingSizeLevel = 50; 
  //content hugging 为1000
  [view setContentHuggingPriority:UILayoutPriorityRequired
                             forAxis:UILayoutConstraintAxisHorizontal];
  
  //content compression 为250
  [view setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
                                           forAxis:UILayoutConstraintAxisHorizontal];
  ```

## 4.6 自动、手动布局选型

> 手动布局的方式，原始落后、界面开发维护效率低，对从事过前端开发的人来说更是难以适应。所以，苹果需要提供更好的界面引擎来提升开发者的体验，Auto Layout 随之出现。

## 4.7 示例: cell 里面 label的高度自适应问题

我把相关内容截取到这里  主要是UILabel的高度会有变化，所以这里主要是说说label变化时如何处理，设置UILabel的时候注意要设置preferredMaxLayoutWidth这个宽度，还有ContentHuggingPriority为UILayoutPriorityRequried  

```objectivec
CGFloat maxWidth = [UIScreen mainScreen].bounds.size.width - 10 * 2;
textLabel = [UILabel new];
textLabel.numberOfLines = 0;
textLabel.preferredMaxLayoutWidth = maxWidth;
[self.contentView addSubview:textLabel];

[textLabel mas_makeConstraints:^(MASConstraintMaker *make) {
  make.top.equalTo(statusView.mas_bottom).with.offset(10);
  make.left.equalTo(self.contentView).with.offset(10);
  make.right.equalTo(self.contentView).with.offset(-10);
  make.bottom.equalTo(self.contentView).with.offset(-10);
}];
[_contentLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
```

如果版本支持最低版本为iOS 8以上的话可以直接利用UITableViewAutomaticDimension在tableview的heightForRowAtIndexPath直接返回即可。

```objectivec
tableView.rowHeight = UITableViewAutomaticDimension;
tableView.estimatedRowHeight = 80; //减少第一次计算量，iOS7后支持

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
  // 只用返回这个！
  return UITableViewAutomaticDimension;
}
```

  但如果需要兼容iOS 8之前版本的话，就要回到老路子上了，主要是用systemLayoutSizeFittingSize来取高。

步骤是先在数据model中添加一个height的属性用来缓存高，然后在table view的heightForRowAtIndexPath代理里static一个只初始化一次的Cell实例，然后根据model内容填充数据，最后根据cell的contentView的systemLayoutSizeFittingSize的方法获取到cell的高。具体代码如下

```objectivec
//在model中添加属性缓存高度
@interface DataModel : NSObject
@property (copy, nonatomic) NSString *text;
@property (assign, nonatomic) CGFloat cellHeight; //缓存高度
@end

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    static CustomCell *cell;
    //只初始化一次cell
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cell = [tableView dequeueReusableCellWithIdentifier:NSStringFromClass([CustomCell class])];
    });
    DataModel *model = self.dataArray[(NSUInteger) indexPath.row];
    [cell makeupData:model];

    if (model.cellHeight <= 0) {
        //使用systemLayoutSizeFittingSize获取高度
        model.cellHeight = [cell.contentView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].height + 1;
    }
    return model.cellHeight;
}
```
