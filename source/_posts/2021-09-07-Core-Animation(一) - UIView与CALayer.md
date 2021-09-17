---
title: Core Animation(一) - UIView与CALayer
date: 2021-09-07 14:50:38
urlname: core-animation01.html
tags:
categories:
  - 图形处理与渲染
---

Core Animation其实是一个令人误解的命名。你可能认为它只是用来做动画的，但实际上它是从一个叫做*Layer Kit*这么一个不怎么和动画有关的名字演变而来。

Core Animation是一个*复合引擎*，它的职责就是尽可能快地组合屏幕上不同的可视内容，这个内容是被分解成独立的*图层*，存储在一个叫做**图层树**的体系之中。于是这个树形成了**UIKit**以及在iOS应用程序当中你所能在屏幕上看见的一切的基础。

## 一、View与Layer

### 1.1 CALayer图层

> CALayer： 管理基于图像的内容，并允许你对该内容执行动画

在 iOS 中，所有的 view 都是由一个底层的 layer 来驱动的。view 和它的 layer 之间有着紧密的联系，view 其实直接从 layer 对象中获取了绝大多数它所需要的数据。layer给view提供了基础设施，使得绘制内容和呈现更高效动画更容易、更低耗；layer不参与view的事件处理、不参与响应链。

<img src="/images/caa/7.5.png" alt="" style="zoom:100%;" />

UIKit 中的每个视图都有自己的 CALayer 。 这个图层通常有一个缓存区/后备存储(Backing Store)，它是像素位图。这个后备存储实际上是渲染到显示器上的。

> 术语“后备存储”通常用于图形用户界面的上下文中。 是一块记忆，其中包含窗户的图像。 如果窗口被覆盖（甚至部分）然后被覆盖，则后备存储用于重绘。

> 测试：分别修改、打印MyView与.layer的backgroundColor，可以看到这两者是同步变化的。**所以其实UIView的背景色就是CALayer的背景色。**

为什么iOS要基于`UIView`和`CALayer`提供两个平行的层级关系呢？为什么不用一个简单的层级来处理所有事情呢？原因在于要做职责分离，这样也能避免很多重复代码。

- 在iOS和Mac OS两个平台上，事件和用户交互有很多地方的不同，基于多点触控的用户界面和基于鼠标键盘有着本质的区别，这就是为什么iOS有UIKit和`UIView`，但是Mac OS有AppKit和`NSView`的原因。他们功能上很相似，但是在实现上有着显著的区别。

- 绘图，布局和动画，相比之下就是类似Mac笔记本和桌面系列一样应用于iPhone和iPad触屏的概念。把这种功能的逻辑分开并应用到独立的Core Animation框架，苹果就能够在iOS和Mac OS之间共享代码，使得对苹果自己的OS开发团队和第三方开发者去开发两个平台的应用更加便捷。

### 1.2 四个层级关系

在整个Core Animation机制中，存在4个层级关系：

#### 1.2.1 视图层级

视图在层级关系中可以互相嵌套，一个视图可以管理它的所有子视图的位置。

#### 1.2.2 图层树

每一个`UIView`都有一个`CALayer`实例的图层属性，也就是所谓的*backing layer*，视图的职责就是创建并管理这个图层，以确保当子视图在层级关系中添加或者被移除的时候，他们关联的图层也同样对应在层级关系树当中有相同的操作

#### 1.2.3 呈现树

在iOS中，屏幕每秒钟重绘60次。如果动画时长比60分之一秒要长，Core Animation就需要在设置一次新值和新值生效之间，对屏幕上的图层进行重新组织。这意味着`CALayer`除了“真实”值（就是你设置的值）之外，必须要知道当前*显示*在屏幕上的属性值的记录。

每个图层属性的显示值都被存储在一个叫做*呈现图层*的独立图层当中，他可以通过`-presentationLayer`方法来访问。这个呈现图层实际上是模型图层的复制，但是它的属性值代表了在任何指定时刻当前外观效果。换句话说，你可以通过呈现图层的值来获取当前屏幕上真正显示出来的值。

呈现树通过图层树中所有图层的呈现图层所形成。注意呈现图层仅仅当图层首次被*提交*（就是首次第一次在屏幕上显示）的时候创建，所以在那之前调用`-presentationLayer`将会返回`nil`。

#### 1.2.4 渲染树

详见[下下篇 iOS渲染流程探究](https://tenloy.github.io/2021/09/11/core-animation03.html)

图层树的改动会在Application这一层以事务的形式完成打包提交，一旦打包的图层和动画到达渲染服务进程，他们会被反序列化来形成另一个叫做*渲染树*的图层树。使用这个树状结构，渲染服务对动画的每一帧做出如下工作：

- 对所有的图层属性计算中间值，设置OpenGL几何形状（纹理化的三角形）来执行渲染
- 在屏幕上渲染可见的三角形

## 二、View的绘制

> 苹果文档 —— [The View Drawing Cycle](https://developer.apple.com/library/archive/documentation/WindowsViews/Conceptual/ViewPG_iPhoneOS/WindowsandViews/WindowsandViews.html)

### 2.1 绘制机制

UIView 类使用按需绘制模型来呈现内容。

- 当一个视图第一次出现在屏幕上时，系统要求它绘制它的内容。系统捕获此内容的快照并将该快照用作视图的视觉表示。
- 如果您从不更改视图的内容，则视图的绘制代码可能永远不会被再次调用。大多数涉及视图的操作都会重复使用快照图像。
- 如果您确实更改了内容，则会通知系统视图已更改。然后视图重复绘制视图和捕获新结果的快照的过程。

当视图的内容发生更改时，不要直接重绘这些更改。可以使用 setNeedsDisplay 或 setNeedsDisplayInRect: 方法使视图无效。这些方法告诉系统视图的内容发生了变化，需要在下一次重绘。

### 2.2 绘制周期

**系统会等到当前 run loop 执行结束(一个loop也就是一个绘制周期)，才启动任何绘图操作**。这种延迟使您有机会一次性使多个视图无效、在层次结构中添加或删除视图、隐藏视图、调整视图大小和重新定位视图。然后，所做的所有更改都会同时反映出来。

### 2.3 Custom Drawing

> 寄宿图：CALayer类除了简单的设置背景颜色外，还能够包含一张图片。又称CALayer的寄宿图（即图层中包含的图）。

当需要渲染视图的内容时，实际的绘制过程取决于视图及其配置。系统视图通常实现私有绘图方法来呈现其内容。这些相同的系统视图经常公开接口，您可以使用这些接口来配置视图的实际外观。

- 直接设置layer的contents属性
- 对于自定义 UIView 子类，可以重写 drawRect: 方法并使用该方法绘制视图的内容。（最常用）

#### 2.3.1 contents属性

CALayer 有一个属性叫做`contents`，这个属性的类型被定义为id，意味着它可以是任何类型的对象。在这种情况下，你可以给`contents`属性赋任何值，你的app都能够编译通过。但是，在实践中，如果你给`contents`赋的不是CGImage，那么你得到的图层将是空白的。

`contents`这个奇怪的表现是由Mac OS的历史原因造成的。它之所以被定义为id类型，是因为在Mac OS系统上，这个属性对CGImage和NSImage类型的值都起作用。如果你试图在iOS平台上将UIImage的值赋给它，只能得到一个空白的图层。一些初识Core Animation的iOS开发者可能会对这个感到困惑。

头疼的不仅仅是我们刚才提到的这个问题。事实上，你真正要赋值的类型应该是CGImageRef，它是一个指向CGImage结构的指针。UIImage有一个CGImage属性，它返回一个"CGImageRef",如果你想把这个值直接赋值给CALayer的`contents`，那你将会得到一个编译错误。因为CGImageRef并不是一个真正的Cocoa对象，而是一个Core Foundation类型。

尽管Core Foundation类型跟Cocoa对象在运行时貌似很像（被称作toll-free bridging），它们并不是类型兼容的，不过你可以通过bridged关键字转换。如果要给图层的寄宿图赋值，你可以按照以下这个方法：

```
layer.contents = (__bridge id)image.CGImage;
```

如果你没有使用ARC（自动引用计数），你就不需要__bridge这部分。但是，你干嘛不用ARC？！

#### 2.3.2 drawRect

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

## 三、View的重绘

### 3.1 重绘流程图

写在前面：注意：**更改视图的几何形状不会自动导致系统重绘视图的内容**。视图的内容模式(contentMode)属性决定了如何解释视图几何的变化。大多数content modes会在视图边界内拉伸或重新定位现有快照，并且不会创建新快照。有关内容模式如何影响视图的绘制周期的更多信息，请参阅[Content Modes](https://developer.apple.com/library/archive/documentation/WindowsViews/Conceptual/ViewPG_iPhoneOS/WindowsandViews/WindowsandViews.html)。

先来看一下**更新-绘制流程图**，然后梳理一下其中的重要方法

<img src="/images/caa/viewredraw.png" alt="viewredraw" style="zoom:80%;" />

- 当我们调用 `[UIView setNeedsDisplay]` 这个方法时，其实并没有立即进行绘制工作，系统会立刻调用CALayer的同名方法，并且**会在当前layer上打上一个标记，然后会在当前runloop将要结束的时候（下一个绘制周期）**调用 `[CALayer display]` 这个方法，然后进入我们视图的真正绘制过程。

- 在 `[CALayer display]` 这个方法的内部实现中会判断这个 layer 的 delegate 是否响应 displayLayer: 这个方法，如果响应这个方法，就会进入到系统绘制流程中；如果不响应这个方法，那么就会为我们提供**异步绘制**的入口。

- 在异步绘制中，会先判断代理是否有实现协议的 `drawLayer:inContext` 方法，如果有实现，就会创建一个空的寄宿图和 Core Craphics 的绘制上下文，为绘制寄宿图做准备。

  ```c
  CGBitmapContextCreate(...);
  // Core Craphics API...
  CGBitmapContextCreateImage(...);
  ```

  然后会在一个合适的时候调用一个我们非常熟悉的方法`[UIView drawRect:]` 来获取寄宿图内容。`[UIView drawRect:]` 这个方法默认是什么都不做，系统给我们开这个口子是为了让我们可以再做一些其他的绘制工作。

- 无论是哪个分支，**最终都会由CALayer上传对应的backing store(寄宿图，也即位图bitmap)给GPU**，然后就结束了本次绘制流程。

### 3.2 内容重绘 — Layer方法

#### 3.2.1 -display

重新加载该图层的内容。调用 -drawInContext: 方法，然后更新图层的'contents'属性。

通常这不会被直接调用。

#### 3.2.2 -setNeedsDisplay

将图层的内容标记为需要更新。

调用此方法会导致图层重新缓存其内容。 这导致图层可能调用其委托的 displayLayer: 或 drawLayer:inContext: 方法。 删除图层 contents 属性中的现有内容，为新内容让路。

```objectivec
// 重绘范围是整个边界矩形
- (void)setNeedsDisplay;
// 重绘范围是参数指定的矩形(应在接收器的坐标系中指定, 且只对该图层有效)
- (void)setNeedsDisplayInRect:(CGRect)rect;
```

#### 3.2.3 -drawInContext:

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

#### 3.2.4 CALayerDelegate

```objectivec
@protocol CALayerDelegate <NSObject>
@optional

/* 如果定义了，则由layer的-display方法的默认实现调用，在这种情况下，它应该实现整个 display 过程(通常通过设置' contents'属性)。*/
- (void)displayLayer:(CALayer *)layer;

/* 如果定义了，则由layer的-drawInContext的默认实现调用 */
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

### 3.3 内容重绘 — View方法

#### 3.3.1 -setNeedsDisplay

通知系统你的视图内容需要重绘。此方法将指定的矩形添加到视图的当前无效矩形列表中并立即返回。直到下一个绘制周期才会真正重绘视图，此时所有无效的视图都会更新。

你应该仅在视图的内容或外观发生更改时，使用此方法请求重绘视图。**如果只是更改视图的几何形状，通常不会重新绘制视图，它的现有内容根据视图的 contentMode 属性中的值进行调整。**

 注意：如果您的视图由 CAEAGLLayer 对象支持，则此方法无效。它仅适用于使用原生绘图技术（例如 UIKit 和 Core Graphics）来呈现其内容的视图。

```objectivec
// 重绘范围是整个边界矩形
- (void)setNeedsDisplay;
// 重绘范围是参数指定的矩形(应在接收器的坐标系中指定, 且只对该图层有效)
- (void)setNeedsDisplayInRect:(CGRect)rect;
```

### 3.4 布局重新计算 — Layer方法

#### 3.4.1 -layoutSublayers

告诉图层更新其布局 

子类可以覆盖此方法并使用它来实现自己的布局算法。您的实现必须设置每个子层的frame。

此方法的默认实现：

- 如果 layer 有delegate对象，且实现了 layoutSublayersOfLayer: 方法，调用它。

- 否则，该方法调用 layoutManager 属性对象(Mac OS API)的 layoutSublayersOfLayer: 方法。 

#### 3.4.2 -setNeedsLayout(做标记)

使图层的布局无效并将其标记为需要更新。会在下一个更新周期中触发布局更新。系统调用任何需要布局更新的图层的 layoutSublayers 方法。

当图层的边界发生变化或添加或删除子图层时，系统通常会自动调用此方法。   

#### 3.4.3 -layoutIfNeeded(立即)

 如果需要，立即重新计算图层的布局。

 收到此消息后，将遍历该图层的父图层，直到找到不需要布局的祖先图层。然后在该祖先下的整个层树上执行布局。

### 3.5 布局重新计算 — View方法

#### 3.5.1 -layoutSubviews

默认实现使用您设置的任何约束来确定每一个子视图的大小和位置。

子类可以根据需要覆盖此方法以对其子视图执行更精确的布局。 仅当子视图的自动调整大小和基于约束的行为不提供您想要的行为时，您才应该覆盖此方法。 您可以使用您的实现直接设置子视图的框架矩形。

您**不应直接调用**此方法。 如果要强制更新布局，请在下一次绘图更新之前调用 setNeedsLayout 方法。 如果您想立即更新视图的布局，请调用 layoutIfNeeded 方法。

#### 3.5.2 -setNeedsLayout(做标记)

使当前布局无效并在下一个更新周期触发布局更新。

当您想要调整视图子视图的布局时，请**在应用程序的主线程上调用此方法**。此方法记录请求并立即返回。

由于此方法不会强制立即更新，而是等待下一个更新周期，因此您可以使用它在更新任何视图之前使多个视图的布局无效。此行为**允许您将所有布局更新合并到一个更新周期，这通常对性能更好**。

#### 3.5.3 -layoutIfNeeded(立即)

如果有待办的(pending)布局更新，则立即布局子视图。

使用此方法强制视图立即更新其布局。使用“自动布局”时，布局引擎会根据需要更新视图的位置，以满足约束的更改。用接收此消息的视图作为根视图开始布局视图子树。

如果没有待处理的布局更新，则此方法退出而不修改布局或调用任何与布局相关的回调。