---
title: Core Animation(二) - 隐式动画、CATransaction与CAAction
date: 2021-09-09 19:36:17
urlname: core-animation02.html
tags:
categories:
  - 图形处理与渲染
---

> [原文地址](https://github.com/qunten/iOS-Core-Animation-Advanced-Techniques/blob/master/7-%E9%9A%90%E5%BC%8F%E5%8A%A8%E7%94%BB/%E9%9A%90%E5%BC%8F%E5%8A%A8%E7%94%BB.md) 译自《iOS Core Animation Advanced Techniques》

动画是Core Animation库一个非常显著的特性。这一章我们来看看它是怎么工作的。具体来说，我们先来讨论框架自动实现的*隐式动画*（除非你明确禁用了这个功能）。

# 一、可动画、事务与RunLoop

## 1.1 可动画的图层属性

Core Animation基于一个假设，说屏幕上的任何东西都可以（或者可能）做动画。你并不需要在Core Animation中手动打开动画，但是你需要明确地关闭它，否则它会一直存在。

当你改变`CALayer`一个可做动画的属性时，这个改变并不会立刻在屏幕上体现出来。相反，该属性会从先前的值平滑过渡到新的值。这一切都是默认的行为，你不需要做额外的操作 —— 这就是可动画的(隐式动画)。

> 可动画的(animatable)：当改变时，会触发一个从旧的值过渡到新值的简单动画；

**几乎所有的图层的属性都是隐性可动画的。**你可以在文档中看到它们的简介是以 'animatable' 结尾的。这不仅包括了比如位置，尺寸，颜色或者透明度这样的绝大多数的数值属性，甚至也囊括了像 isHidden 和 doubleSided 这样的布尔值。 像 paths 这样的属性也是 animatable 的，但是它不支持隐式动画。

## 1.2 CATransaction(显式/隐式事务)

[CATransaction](https://developer.apple.com/documentation/quartzcore/catransaction)是Core Animation中的事务类，负责批量的把多个对图层树(layer-tree)的修改作为一个原子更新到渲染树。

- 事务是Core Animation用来包含一系列属性动画集合的机制，任何用指定事务去改变可动画的图层属性都不会立刻发生变化，而是当事务一旦**提交**的时候开始用一个动画过渡到新值。
- 事务是通过`CATransaction`类来做管理，这个类的设计有些奇怪，不像你从它的命名预期的那样去管理一个简单的事务，而是管理了一叠你不能访问的事务。`CATransaction`没有属性或者实例方法，并且也不能用`+alloc`和`-init`方法创建它。而是用类方法`+begin`和`+commit`分别来入栈或者出栈。
- 支持嵌套事务。

在iOS中的图层中，**对图层树的每次修改都必须是事务的一部分**。任何可动画的图层属性，发生改变产生的动画都会被添加到栈顶的事务，你可以通过`+setAnimationDuration:`方法设置当前事务的动画时间，或者通过`+animationDuration`方法来获取时长值（默认0.25秒）。

Core Animation支持两种类型的事务：隐式事务和显式事务。

- **当图层树被没有显式事务的线程修改时，隐式事务会自动创建，并在线程的 runloop 下一次迭代时自动提交**。
  - 即Core Animation会监测修改，然后在每个*runloop*周期中自动开始一次新的事务（runloop是iOS负责收集用户输入，处理未完成的定时器或者网络事件，最终重新绘制屏幕的东西），即使你不显式地使用`[CATransaction begin]`开始一次事务，在一个特定runloop循环中的任何属性的变化都会被收集起来，然后做一次0.25秒的动画。
- 当应用程序在修改图层树之前向 CATransaction 类发送 begin() 消息，然后向 CATransaction 类发送 commit() 消息时，就会发生显式事务。

```objectivec
@interface CATransaction : NSObject

// 创建和提交事物（Creating and Committing Transactions）

/* 当前线程创建一个新的事物(Transaction)，可嵌套 */
+ (void)begin;   
/* 提交当前事物中的所有改动，如果事物不存在将会出现异常 */
+ (void)commit;  
/* 提交任意的隐式动画，将被延迟一直到嵌套的显示事物被完成 */
+ (void)flush;   

// 重写动画时间（Overriding Animation Duration and Timing）
/* 获取动画时间，默认0.25秒 */
+ (CFTimeInterval)animationDuration;
/* 设置动画时间 */
+ (void)setAnimationDuration:(CFTimeInterval)dur;

/* 默认nil，设置和获取CAMediaTimingFunction（速度控制函数） */
+ (nullable CAMediaTimingFunction *)animationTimingFunction;
+ (void)setAnimationTimingFunction:(nullable CAMediaTimingFunction *)function;

// 禁止属性更改而触发的action(隐式动画)（Temporarily Disabling Property Animations）
/* 每条线程事物，都有disableActions属性的存取器，即设置和获取方法，默认为false，允许隐式动画 */
+ (BOOL)disableActions;
+ (void)setDisableActions:(BOOL)flag;

// 回调闭包（Getting and Setting Completion Block Objects）
/* 动画完成之后被调用 */
+ (nullable void (^)(void))completionBlock;
+ (void)setCompletionBlock:(nullable void (^)(void))block;

// 管理并发（Managing Concurrency）
/* 两个方法用于动画事物的加锁与解锁 在多线程动画中，保证修改属性的安全 */
+ (void)lock;
+ (void)unlock;

// 设置和获取事物属性（Getting and Setting Transaction Properties）
/* 支持的事务属性包括:"animationDuration"， "animationTimingFunction"， "completionBlock"， "disableActions"。*/
+ (nullable id)valueForKey:(NSString *)key;
+ (void)setValue:(nullable id)anObject forKey:(NSString *)key;

@end
```

# 二、隐式动画

CoreAnimation支持两种类型的动画：显式动画、隐式动画。

- 隐式动画：之所以叫隐式，是因为我们并没有指定任何动画的类型。我们仅仅改变了一个属性，然后Core Animation来决定**如何**并且**何时**去做动画。
- 显式动画：
  - 需要创建一个动画对象，并设置开始和结束值，直到把动画应用到某图层上，动画才开始执行。
  - 显式动画既可以直接对图层属性做动画，也可以覆盖默认的图层行为。

隐式动画底层是显式动画。（*详见3.2节、5.1.1节*）

## 2.1 演示

隐式动画看起来这太棒了，似乎不太真实，我们用一个demo来解释一下：首先和第一章“图层树”一样创建一个蓝色的方块，然后添加一个按钮，随机改变它的颜色。点击按钮，你会发现图层的颜色平滑过渡到一个新值，而不是跳变。代码及显示效果如下：

清单7.1 随机改变图层颜色

```objectivec
@interface ViewController ()

@property (nonatomic, weak) IBOutlet UIView *layerView;
@property (nonatomic, strong) CALayer *colorLayer;

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    //create sublayer
    self.colorLayer = [CALayer layer];
    self.colorLayer.frame = CGRectMake(50.0f, 50.0f, 100.0f, 100.0f);
    self.colorLayer.backgroundColor = [UIColor blueColor].CGColor;
    //add it to our view
    [self.layerView.layer addSublayer:self.colorLayer];
}

- (IBAction)changeColor
{
    //randomize the layer background color
    CGFloat red = arc4random() / (CGFloat)INT_MAX;
    CGFloat green = arc4random() / (CGFloat)INT_MAX;
    CGFloat blue = arc4random() / (CGFloat)INT_MAX;
    self.colorLayer.backgroundColor = [UIColor colorWithRed:red green:green blue:blue alpha:1.0].CGColor;                                                                                       ￼
}

@end
```

<img src="/images/caa/7.1.jpg" alt="" style="zoom:60%;" />

这其实就是所谓的**隐式动画**。当你改变一个属性，Core Animation是如何判断动画类型和持续时间的呢？实际上动画执行的时间取决于当前*事务*的设置，动画类型取决于**图层行为**(**action**)。

我们当然可以用当前事务的`+setAnimationDuration:`方法来修改动画时间，但在这里我们首先起一个新的事务，于是修改时间就不会有别的副作用。因为修改当前事务的时间可能会导致同一时刻别的动画（如屏幕旋转），所以最好还是在调整动画之前压入一个新的事务。

修改后的代码见下方。运行程序，你会发现色块颜色比之前变得更慢了。

```objectivec
// 使用 CATransaction 控制动画时间（代码7.2）
- (IBAction)changeColor
{
    //begin a new transaction
    [CATransaction begin];
    //set the animation duration to 1 second
    [CATransaction setAnimationDuration:1.0];
    //randomize the layer background color
    CGFloat red = arc4random() / (CGFloat)INT_MAX;
    CGFloat green = arc4random() / (CGFloat)INT_MAX;
    CGFloat blue = arc4random() / (CGFloat)INT_MAX;
    self.colorLayer.backgroundColor = [UIColor colorWithRed:red green:green blue:blue alpha:1.0].CGColor;
    ￼//commit the transaction
    [CATransaction commit];
}
```

## 2.2 UIView动画的底层事务

如果你用过`UIView`的动画方法做过一些动画效果，那么应该对这个模式不陌生。`UIView`有两个方法，`+beginAnimations:context:`和`+commitAnimations`，和`CATransaction`的`+begin`和`+commit`方法类似。实际上在`+beginAnimations:context:`和`+commitAnimations`之间所有视图或者图层属性的改变而做的动画都是由于设置了`CATransaction`的原因。

在iOS4中，苹果对UIView添加了一种基于block的动画方法：`+animateWithDuration:animations:`。这样写对做一堆的属性动画在语法上会更加简单，但实质上它们都是在做同样的事情。

`CATransaction`的`+begin`和`+commit`方法在`+animateWithDuration:animations:`内部自动调用，这样block中所有属性的改变都会被事务所包含。这样也可以避免开发者由于对`+begin`和`+commit`匹配的失误造成的风险。

## 2.3 事务完成block

基于`UIView`的block的动画允许你在动画结束的时候提供一个完成的动作。`CATranscation`接口提供的`+setCompletionBlock:`方法也有同样的功能。我们来调整上个例子，在颜色变化结束之后执行一些操作。我们来添加一个完成之后的block，用来在每次颜色变化结束之后切换到另一个旋转90的动画。

示例：在颜色动画完成之后添加一个回调，比如再做一次旋转

```objectivec
- (IBAction)changeColor
{
    //begin a new transaction
    [CATransaction begin];
    //set the animation duration to 1 second
    [CATransaction setAnimationDuration:1.0];
    //add the spin animation on completion
    [CATransaction setCompletionBlock:^{
        //rotate the layer 90 degrees
        CGAffineTransform transform = self.colorLayer.affineTransform;
        transform = CGAffineTransformRotate(transform, M_PI_2);
        self.colorLayer.affineTransform = transform;
    }];
    //randomize the layer background color
    CGFloat red = arc4random() / (CGFloat)INT_MAX;
    CGFloat green = arc4random() / (CGFloat)INT_MAX;
    CGFloat blue = arc4random() / (CGFloat)INT_MAX;
    self.colorLayer.backgroundColor = [UIColor colorWithRed:red green:green blue:blue alpha:1.0].CGColor;
    //commit the transaction
    [CATransaction commit];
}
```

<img src="/images/caa/7.2.jpg" alt="" style="zoom:60%;" />

注意旋转动画要比颜色渐变快得多，这是因为完成块是在颜色渐变的事务提交并出栈之后才被执行，于是，用默认的事务做变换，默认的时间也就变成了0.25秒。

# 三、图层行为(action)

## 3.1 UIView所关联layer禁止隐式动画

在 iOS 中也有一些单独的 layer，比如 `AVCaptureVideoPreviewLayer` 和 `CAShapeLayer`，它们不需要附加到 view 上就可以在屏幕上显示内容。两种情况下其实都是 layer 在起决定作用。

当然了，附加到 view 上的 layer 和单独的 layer 在行为上还是稍有不同的。

- 基本上你改变一个单独的 layer 的任何属性的时候，都会触发一个从旧的值过渡到新值的简单动画（这就是所谓的可动画 `animatable`）。
- 然而，如果你改变的是 view 中 layer 的同一个属性，它只会从这一帧直接跳变到下一帧。尽管两种情况中都有 layer，但是当 layer 附加在 view 上时，它的默认的隐式动画的 layer 行为就不起作用了。

在 Core Animation 编程指南的 “How to Animate Layer-Backed Views” 中，对*为什么*会这样做出了一个解释：

> UIView 默认情况下禁止了 layer 动画，但是在 animation block 中又重新启用了它们

这正是我们所看到的行为；当一个属性在动画 block 之外被改变时，没有动画，但是当属性在动画 block 内被改变时，就带上了动画。对于这是_如何_发生的这一问题的答案十分简单和优雅，它优美地阐明和揭示了 view 和 layer 之间是如何协同工作和被精心设计的。

示例：现在来做个实验，试着直接对UIView关联的图层做动画而不是一个单独的图层。

下面代码是对上面代码的一点修改，移除了`colorLayer`，并且直接设置`layerView`关联图层的背景色。

```objectivec
@interface ViewController ()

@property (nonatomic, weak) IBOutlet UIView *layerView;

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    //set the color of our layerView backing layer directly
    self.layerView.layer.backgroundColor = [UIColor blueColor].CGColor;
}

- (IBAction)changeColor
{
    //begin a new transaction
    [CATransaction begin];
    //set the animation duration to 1 second
    [CATransaction setAnimationDuration:1.0];
    //randomize the layer background color
    CGFloat red = arc4random() / (CGFloat)INT_MAX;
    CGFloat green = arc4random() / (CGFloat)INT_MAX;
    CGFloat blue = arc4random() / (CGFloat)INT_MAX;
    self.layerView.layer.backgroundColor = [UIColor colorWithRed:red green:green blue:blue alpha:1.0].CGColor;
    //commit the transaction
    [CATransaction commit];
}
```

运行程序，你会发现当按下按钮，图层颜色瞬间切换到新的值，而不是之前平滑过渡的动画。发生了什么呢？隐式动画好像被`UIView`关联图层给禁用了。

UIKit建立在Core Animation之上，而Core Animation默认对`CALayer`的所有属性（可动画的属性）做动画，但是`UIView`把它关联的图层的这个特性关闭了。

那么隐式动画是如何被UIKit禁用掉呢？为了更好说明这一点，我们需要知道隐式动画是如何实现的。

## 3.2 CAAction

无论何时，一个可动画的 layer 属性改变时，layer 都会寻找并运行合适的 'action' 来实行这个改变。在 Core Animation 的专业术语中把这种改变属性时`CALayer`自动应用的动画称为action，或者 `CAAction`，中文译作动作，也称行为（**以下统称 行为**）。

<font color='red'>CAAction(行为)通常是一个</font>被Core Animation隐式调用的<font color='red'>显式动画对象</font>（`CAAnimation` 实现了`<CAAction>` 协议）。

### 3.2.1 CALayer与CAAction协议

> CAAction：技术上来说，这是一个接口，并可以用来做各种事情。但是实际中，某种程度上你可以只把它理解为用来处理动画。

> 是一个接口，允许对象响应 CALayer 改变触发的 actions

下面是摘的CALayer中，有关CAAction的部分属性、方法：

```objectivec
/** Action (event handler) protocol. **/
@protocol CAAction
//当一个 action object 被调用时，它接收三个参数：事件的名称、事件发生的对象（layer）以及特定于每种事件类型的命名参数字典。
- (void)runActionForKey:(NSString *)event object:(id)anObject arguments:(nullable NSDictionary *)dict;
@end
  
@interface CAAnimation : NSObject <NSSecureCoding, NSCopying, CAMediaTiming, CAAction>
@end
  
@interface CALayer
@property(nullable, weak) id <CALayerDelegate> delegate;
/* A dictionary mapping keys to objects implementing the CAAction protocol. Default value is nil. */
@property(nullable, copy) NSDictionary<NSString *, id<CAAction>> *actions;
@property(nullable, copy) NSDictionary *style;

+ (nullable id<CAAction>)defaultActionForKey:(NSString *)event;

/*
 * 此方法搜索 layer 的给定action object。Actions 为 layer 定义了一些动态行为。
 * @param event/key action标识符（a key path、外部action名称或预定义action标识符）
 * @return 返回为key提供的action object。该对象必须实现 CAAction 协议
 */
- (id<CAAction>)actionForKey:(NSString *)event;

@end
    
@protocol CALayerDelegate <NSObject>
/* 如果已定义，则由 -actionForKey: 方法的默认实现调用。 */
- (nullable id<CAAction>)actionForLayer:(CALayer *)layer forKey:(NSString *)event;
@end
```

CALayer 的 animatable 属性通常都具有相应的 action object 来启动实际动画，也就是说**当 `CALayer` 改变属性时会自动应用动画**。

当`CALayer`的属性被修改时候，它会调用`-actionForKey:`方法，传递属性的名称。来查找到与该属性名称关联的 action object （遵守 CAAction 协议，并能接收 `run(forKey:object:arguments:)` 消息）并执行它。

您还可以将自定义 action objects 与你的 layer 相关联，以实现一些 APP 特定的操作。

### 3.2.2 actionForKey:查找流程

layer 将像 [CALayer 的 actionForKey: 文档](https://developer.apple.com/documentation/quartzcore/calayer/1410844-actionforkey) 中所写的的那样去寻找对应属性变化的 action，整个过程分为四个步骤：

1. 如果该 layer 具有实现 `actionForLayer:forKey:` 方法的 delegate，则 layer 调用该方法并返回结果。delegate 可以通过返回以下三者之一来进行响应：
   - 返回给定 key 的 action object，这种情况下 layer 将使用这个行为。
   - 如果它不处理 action，则返回 NSNull 对象，告诉 layer 这里不需要执行一个行为，明确地强制不再进行进一步的搜索。
   - 返回一个 `nil`， 这样 layer 就会到其他地方继续寻找。
2. 如果没有委托，或者委托没有实现`-actionForLayer:forKey`方法，图层接着检查包含属性名称对应行为映射的`actions`字典。
3. 如果`actions`字典没有包含对应的属性，那么图层接着在它的`style`字典接着搜索属性名。
4. 最后，如果在`style`里面也找不到对应的行为，那么图层将会直接调用定义了每个属性的标准行为的`-defaultActionForKey:`方法。

如果上述任何步骤返回 NSNull 的实例，则在继续之前将其转换为 nil。

所以一轮完整的搜索结束之后，`-actionForKey:`要么返回空（这种情况下将不会有动画发生），要么是`CAAction`协议对应的对象，最后`CALayer`拿这个结果去对先前和当前的值做动画。

**注意：上面的步骤，是对于单独的 layer 来说的。对于 view 中的 layer，对行为的搜索只会到第一步为止（至少我没有见过 view 返回一个 `nil` 然后仍然继续搜索行为的情况）。**

让这一切变得有趣的是，当 layer 在背后支持一个 view 的时候，view 就是它的 delegate；

> 在 iOS 中，如果 layer 与一个 UIView 对象关联时，这个属性`必须`被设置为持有这个 layer 的那个 view。

理解这些之后，就很容易解释UIKit是如何禁用隐式动画的：属性改变时 layer 会向 view 请求一个行为，而一般情况下 view 将返回一个 `NSNull`，只有当属性改变发生在动画 block 中时，view 才会返回实际的行为。

### 3.2.3 验证示例1

对一个一般来说可以动画的 layer 属性向 view 询问行为就可以了，比如对于 'position'：

```objectivec
NSLog(@"outside animation block: %@",
      [myView actionForLayer:myView.layer forKey:@"position"]);

[UIView animateWithDuration:0.3 animations:^{
    NSLog(@"inside animation block: %@",
          [myView actionForLayer:myView.layer forKey:@"position"]);
}];
```

运行上面的代码，可以看到在 block 外 view 返回的是 NSNull 对象，而在 block 中时返回的是一个 CABasicAnimation。很优雅，对吧？值得注意的是打印出的 NSNull 是带着一对尖括号的 ("`<null>`")，这和其他对象一样，而打印 nil 的时候我们得到的是普通括号(`(null)`)：

```objectivec
outside animation block: <null>
inside animation block: <CABasicAnimation: 0x8c2ff10>
```

### 3.2.4 验证示例2

```objectivec
@interface ViewController ()
@property (nonatomic, weak) IBOutlet UIView *layerView;
@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    //test layer action when outside of animation block
    NSLog(@"Outside: %@", [self.layerView actionForLayer:self.layerView.layer forKey:@"backgroundColor"]);
    //begin animation block
    [UIView beginAnimations:nil context:nil];
    //test layer action when inside of animation block
    NSLog(@"Inside: %@", [self.layerView actionForLayer:self.layerView.layer forKey:@"backgroundColor"]);
    //end animation block
    [UIView commitAnimations];
}

@end
```

运行程序，控制台显示结果如下：

```
$ LayerTest[21215:c07] Outside: <null>
$ LayerTest[21215:c07] Inside: <CABasicAnimation: 0x757f090>
```

## 3.3 +setDisableActions

当然返回`NSNull`并不是禁用隐式动画唯一的办法，`CATransaction`有个方法叫做`+setDisableActions:`，可以用来对所有属性打开或者关闭隐式动画。如果在*代码7.2*的`[CATransaction begin]`之后添加下面的代码，同样也会阻止动画的发生：

```objectivec
[CATransaction setDisableActions:YES];
```

## 3.4 小结

总结一下，我们知道了如下几点

- `UIView`关联的图层禁用了隐式动画，对这种图层做动画的唯一办法就是使用`UIView`的动画函数（而不是依赖`CATransaction`），或者继承`UIView`，并覆盖`-actionForLayer:forKey:`方法，或者直接创建一个显式动画。
- 对于单独存在的图层，我们可以通过实现图层的`-actionForLayer:forKey:`委托方法，或者提供一个`actions`字典来控制隐式动画。

我们来对颜色渐变的例子使用一个不同的行为，通过给`colorLayer`设置一个自定义的`actions`字典。我们也可以使用委托来实现，但是`actions`字典可以写更少的代码。那么到底改如何创建一个合适的行为对象呢？

## 3.5 自定义图层属性行为

行为通常是一个被Core Animation*隐式*调用的*显式*动画对象。这里我们使用的是一个实现了`CATransition`的实例，叫做*推进过渡*（代码如下）。

显式动画中的过渡，不再赘述，对于现在，只要知道`CATransition`响应`CAAction`协议，并且可以当做一个图层行为就足够了。结果很赞，不论在什么时候改变背景颜色，新的色块都是从左侧滑入，而不是默认的渐变效果。

实现自定义行为：

```objectivec
@interface ViewController ()

@property (nonatomic, weak) IBOutlet UIView *layerView;
@property (nonatomic, strong) CALayer *colorLayer;

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    //create sublayer
    self.colorLayer = [CALayer layer];
    self.colorLayer.frame = CGRectMake(50.0f, 50.0f, 100.0f, 100.0f);
    self.colorLayer.backgroundColor = [UIColor blueColor].CGColor;
    //add a custom action
    CATransition *transition = [CATransition animation];
    transition.type = kCATransitionPush;
    transition.subtype = kCATransitionFromLeft;
    self.colorLayer.actions = @{@"backgroundColor": transition};
    //add it to our view
    [self.layerView.layer addSublayer:self.colorLayer];
}

- (IBAction)changeColor
{
    //randomize the layer background color
    CGFloat red = arc4random() / (CGFloat)INT_MAX;
    CGFloat green = arc4random() / (CGFloat)INT_MAX;
    CGFloat blue = arc4random() / (CGFloat)INT_MAX;
    self.colorLayer.backgroundColor = [UIColor colorWithRed:red green:green blue:blue alpha:1.0].CGColor;
}

@end
```

使用推进过渡的色值动画：

<img src="/images/caa/7.3.jpg" alt="" style="zoom:60%;" />

# 四、呈现图层与模型图层

## 4.1 presentationLayer与modelLayer

`CALayer`的属性行为其实很不正常，因为改变一个图层的属性并没有立刻生效，而是通过一段时间渐变更新。这是怎么做到的呢？

当你改变一个图层的属性，属性值的确是立刻更新的（如果你读取它的数据，你会发现它的值在你设置它的那一刻就已经生效了），但是屏幕上并没有马上发生改变。这是因为你设置的属性并没有直接调整图层的外观，相反，他只是定义了图层动画结束之后将要变化的外观。

当设置`CALayer`的属性，实际上是在定义当前事务结束之后图层如何显示的**模型**。这里就是一个典型的**微型MVC模式**：

- Core Animation扮演了一个**控制器**的角色，并且负责根据图层行为和事务设置去不断更新**视图**的这些属性在屏幕上的状态。
- `CALayer`是一个连接用户界面（就是MVC中的**view**）虚构的类，但是在界面本身这个场景下，`CALayer`的行为更像是存储了视图如何显示和动画的数据模型。
- 实际上，在苹果自己的文档中，图层树通常都是指的图层树模型。

在iOS中，屏幕每秒钟重绘60次。如果动画时长比60分之一秒要长，Core Animation就需要在设置一次新值和新值生效之间，对屏幕上的图层进行重新组织。这意味着`CALayer`除了“真实”值（就是你设置的值）之外，必须要知道**当前显示**在屏幕上的属性值的记录。

每个图层属性的显示值都被存储在一个叫做**呈现图层**的独立图层当中，他可以通过`-presentationLayer`方法来访问。这个呈现图层实际上是模型图层的复制，但是它的属性值代表了在任何指定时刻当前外观效果。换句话说，你可以**通过呈现图层的值来获取当前屏幕上真正显示出来的值**。

如图，一个移动的图层是如何通过数据模型呈现的：

<img src="/images/caa/7.4.jpg" alt="" style="zoom:60%;" />

我们在本书的第一章中提到除了图层树，另外还有*呈现树*。**呈现树通过图层树中所有图层的呈现图层所形成**。注意呈现图层仅仅当图层首次被**提交**（就是首次第一次在屏幕上显示）的时候创建，所以在那之前调用`-presentationLayer`将会返回`nil`。

你可能注意到有一个叫做`–modelLayer`的方法。在呈现图层上调用`–modelLayer`将会返回它正在呈现所依赖的`CALayer`。通常在一个图层上调用`-modelLayer`会返回`–self`（实际上我们已经创建的原始图层就是一种数据模型）。

## 4.2 呈现图层的使用场景

大多数情况下，你不需要直接访问呈现图层，你可以通过和模型图层的交互，来让Core Animation更新显示。两种情况下呈现图层会变得很有用，一个是同步动画，一个是处理用户交互。

- 如果你在实现一个基于定时器的动画（见第11章“基于定时器的动画”），而不仅仅是基于事务的动画，这个时候准确地知道在某一时刻图层显示在什么位置就会对正确摆放图层很有用了。
- 如果你想让你做动画的图层响应用户输入，你可以使用`-hitTest:`方法（见第三章“图层几何学”）来判断指定图层是否被触摸，这时候对**呈现图层**而不是**模型图层**调用`-hitTest:`会显得更有意义，因为呈现图层代表了用户当前看到的图层位置，而不是当前动画结束之后的位置。

我们可以用一个简单的案例来证明后者（代码如下）。在这个例子中，点击屏幕上的任意位置将会让图层平移到那里。点击图层本身可以随机改变它的颜色。我们通过对呈现图层调用`-hitTest:`来判断是否被点击。

如果修改代码让`-hitTest:`直接作用于*colorLayer*而不是呈现图层，你会发现当图层移动的时候它并不能正确工作。这时候你就需要点击图层将要移动到的位置而不是图层本身来响应点击（这就是**用呈现图层来响应hit test**的原因）。

使用`presentationLayer`图层来判断当前图层位置：

```objectivec
@interface ViewController ()

@property (nonatomic, strong) CALayer *colorLayer;

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    //create a red layer
    self.colorLayer = [CALayer layer];
    self.colorLayer.frame = CGRectMake(0, 0, 100, 100);
    self.colorLayer.position = CGPointMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2);
    self.colorLayer.backgroundColor = [UIColor redColor].CGColor;
    [self.view.layer addSublayer:self.colorLayer];
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    //get the touch point
    CGPoint point = [[touches anyObject] locationInView:self.view];
    //check if we've tapped the moving layer
    if ([self.colorLayer.presentationLayer hitTest:point]) {
        //randomize the layer background color
        CGFloat red = arc4random() / (CGFloat)INT_MAX;
        CGFloat green = arc4random() / (CGFloat)INT_MAX;
        CGFloat blue = arc4random() / (CGFloat)INT_MAX;
        self.colorLayer.backgroundColor = [UIColor colorWithRed:red green:green blue:blue alpha:1.0].CGColor;
    } else {
        //otherwise (slowly) move the layer to new position
        [CATransaction begin];
        [CATransaction setAnimationDuration:4.0];
        self.colorLayer.position = point;
        [CATransaction commit];
    }
}
@end
```

# 五、实践篇

> 原文 — [View-Layer 协作](https://objccn.io/issue-12-4/)

## 5.1 从 UIKit 中学习

我很确定我们都会同意 UIView 动画是一组非常优秀的 API，它简洁明确。实际上，它使用了 Core Animation 来执行动画，这给了我们一个绝佳的机会来深入研究 UIKit 是如何使用 Core Animation 的。在这里甚至还有很多非常棒的实践和技巧可以让我们借鉴。:)

### 5.1.1 addAnimation:forKey:

当属性在动画 block 中改变时，view 将向 layer 返回一个基本动画，然后动画通过图层的 `addAnimation:forKey:` 方法被添加到 layer 中，就像显式地添加动画那样。再一次，别直接信我，让我们实践检验一下。

归功于 UIView 的 `+layerClass` 类方法，view 和 layer 之间的交互很容易被观测到。通过这个方法我们可以在为 view 创建 layer 时为其指定要使用的类。通过子类一个 UIView，以及用这个方法返回一个自定义的 layer 类，我们就可以重写 layer 子类中的 `addAnimation:forKey:` 并输出一些东西来验证它是否确实被调用。唯一要记住的是我们需要调用 super 方法，不然的话我们就把要观测的行为完全改变了：

```objectivec
@interface DRInspectionLayer : CALayer
@end

@implementation DRInspectionLayer
- (void)addAnimation:(CAAnimation *)anim forKey:(NSString *)key
{
    NSLog(@"adding animation: %@", [anim debugDescription]);
    [super addAnimation:anim forKey:key];
}
@end


@interface DRInspectionView : UIView
@end

@implementation DRInspectionView
+ (Class)layerClass
{
    return [DRInspectionLayer class];
}
@end
```

通过输出动画的 debug 信息，我们不仅可以验证它确实如预期一样被调用了，还可以看到动画是如何组织构建的：

```objectivec
<CABasicAnimation:0x8c73680; 
    delegate = <UIViewAnimationState: 0x8e91fa0>;
    fillMode = both; 
    timingFunction = easeInEaseOut; 
    duration = 0.3; 
    fromValue = NSPoint: {5, 5}; 
    keyPath = position
>
```

当动画刚被添加到 layer 时，属性的新值还没有被改变。在构建动画时，只有 `fromValue` (也就是当前值) 被显式地指定了。[CABasicAnimation 的文档](https://developer.apple.com/library/ios/documentation/GraphicsImaging/Reference/CABasicAnimation_class/Introduction/Introduction.html)向我们简单介绍了这么做对于动画的插值来说，意味着什么：

> fromValue、toValue、byValue三个对象定义了要插入的属性值。三者都是可选的，并且最多两个非nil。
>
> 当只有 `fromValue` 不是 `nil` 时，在 `fromValue` 和属性当前显示层的值之间进行插值。
>
> 插值指利用某一个函数来计算出2个或更多的值之间的值，最简单的比如算术平均数(x+y)/2就是x,y的线性插值。在图形图像中例如旋转，放大，缩小等操作中，往往变化后图像中的点对应源图片中的点是不存在的，例如（2.1，3）这个点，那么在计算目标图像的在该点像素值的时候，就 需要进行插值运算来计算出该点的像素值。

这也是我在处理显式动画时选择的做法，将一个属性改变为新的值，然后将动画对象添加到 layer 上：

```objectivec
CABasicAnimation *fadeIn = [CABasicAnimation animationWithKeyPath:@"opacity"];
fadeIn.duration  = 0.75;
fadeIn.fromValue = @0;

myLayer.opacity = 1.0; // 更改 model 的值 ...
// ... 然后添加动画对象
[myLayer addAnimation:fadeIn forKey:@"fade in slowly"];
```

这很简洁，你也不需要在动画被移除的时候做什么额外操作。如果动画是在一段延迟后才开始的话，你可以使用 backward 填充模式 (或者 'both' 填充模式)，就像 UIKit 所创建的动画那样。

### 5.1.2 UIViewAnimationState类

可能你看见上面输出中的动画的 delegate 了，想知道这个 UIViewAnimationState 类是用来做什么的吗？

在此之前，先来看一下这个 CAAnimationDelegate 协议：

```objectivec
@interface CAAnimation : NSObject <NSSecureCoding, NSCopying, CAMediaTiming, CAAction>
@property(nullable, strong) id <CAAnimationDelegate> delegate;
@end

@protocol CAAnimationDelegate <NSObject>
@optional
/* Called when the animation begins its active duration. */
- (void)animationDidStart:(CAAnimation *)anim;

/* Called when the animation either completes its active duration or is removed from the object
 * it is attached to (i.e. the layer). 'flag' is true if the animation reached the end of its active 
 * duration without being removed. */
- (void)animationDidStop:(CAAnimation *)anim finished:(BOOL)flag;

@end
```

然后我们可以来看看这个实现了上次协议的类做了什么，[dump 出来的头文件](https://github.com/rpetrich/iphoneheaders/blob/master/UIKit/UIViewAnimationState.h)：

```objectivec
@interface UIViewAnimationState : NSObject {
    UIViewAnimationState* _nextState;
    NSString* _animationID;
    void* _context;
    id _delegate;  // 
    double _duration;
    double _delay;
    double _frameInterval;
    double _start;
    int _curve;
    float _repeatCount;
    int _transition;
    UIView* _transitionView;
  #if __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_3_2
    int _filter;
    UIView* _filterView;
    float _filterValue;	
  #endif
    SEL _willStartSelector;
    SEL _didEndSelector;
    int _didEndCount;
    CGPoint _position;
    unsigned _willStartSent : 1;
    unsigned _useCurrentLayerState : 1;
    unsigned _cacheTransition : 1;
    unsigned _autoreverses : 1;
    unsigned _roundsToInteger : 1;
  #if __IPHONE_OS_VERSION_MAX_ALLOWED < __IPHONE_3_2
    unsigned _reserved : 27;
  #endif
}
+ (void)pushViewAnimationState:(id)state context:(void*)context;
+ (void)popAnimationState;
- (void)dealloc;
- (void)setAnimationAttributes:(id<CAMediaTiming>)attributes;	// save the attributes of the animation state *into* the argument.
- (void)animationDidStart:(id)animation;
- (void)sendDelegateAnimationDidStop:(id)sendDelegateAnimation finished:(BOOL)finished;
- (void)animationDidStop:(id)animation finished:(BOOL)finished;
@end
```

可以看到，它主要用来维护动画的一些状态 (持续时间，延时，重复次数等等)。它还负责对一个栈做 push 和 pop，这是为了在多个动画 block 嵌套时能够获取正确的动画状态。这些都是些实现细节，除非你想要写一套自己的基于 block 的动画 API，否则可能你不会用到它们 (实际上这是一个很有趣的点子)。

然后真正*有意思*的是这个 delegate 实现了 `animationDidStart:` 和 `animationDidStop:finished:`，并将信息传给了它自己的 delegate。

> **编者注** 这里不太容易理解，加以说明：从上面的头文件中可以看出，作为 CAAnimation 的 delegate 的私有类 `UIViewAnimationState` 中还有一个 `_delegate` 成员，并且 `animationDidStart:` 和 `animationDidStop:finished:` 也是典型的 delegate 的实现方法。

### 5.1.3 UIViewAnimationBlockDelegate类

通过打印这个 delegate 的 delegate，我们可以发现它也是一个私有类：UIViewAnimationBlockDelegate。同样进行 [class dump 得到它的头文件](https://github.com/EthanArbuckle/IOS-7-Headers/blob/master/Frameworks/UIKit.framework/UIViewAnimationBlockDelegate.h)，这是一个很小的类，只负责一件事情：响应动画的 delegate 回调并且执行相应的 block。如果我们使用自己的 Core Animation 代码，并且选择 block 而不是 delegate 做回调的话，添加这个是很容易的：

```objectivec
@interface DRAnimationBlockDelegate : NSObject

@property (copy) void(^start)(void);
@property (copy) void(^stop)(BOOL);

+(instancetype)animationDelegateWithBeginning:(void(^)(void))beginning
                                   completion:(void(^)(BOOL finished))completion;

@end

@implementation DRAnimationBlockDelegate

+ (instancetype)animationDelegateWithBeginning:(void (^)(void))beginning
                                    completion:(void (^)(BOOL))completion
{
    DRAnimationBlockDelegate *result = [DRAnimationBlockDelegate new];
    result.start = beginning;
    result.stop  = completion;
    return result;
}

- (void)animationDidStart:(CAAnimation *)anim
{
    if (self.start) {
        self.start();
    }
    self.start = nil;
}

- (void)animationDidStop:(CAAnimation *)anim finished:(BOOL)flag
{
    if (self.stop) {
        self.stop(flag);
    }
    self.stop = nil;
}

@end
```

虽然是我个人的喜好，但是我觉得像这样的基于 block 的回调风格可能会比实现一个 delegate 回调更适合你的代码：

```objectivec
fadeIn.delegate = [DRAnimationBlockDelegate animationDelegateWithBeginning:^{
    NSLog(@"beginning to fade in");
} completion:^(BOOL finished) {
    NSLog(@"did fade %@", finished ? @"to the end" : @"but was cancelled");
}];
```

## 5.2 自定义基于 block 的动画 APIs

一旦你知道了 `actionForKey:` 的机理之后，UIView 就远没有它一开始看起来那么神秘了。实际上我们完全可以按照我们的需求量身定制地写出一套自己的基于 block 的动画 APIs。我所设计的动画将通过在 block 中用一个很激进的时间曲线来做动画，以吸引用户对该 view 的注意，之后做一个缓慢的动画回到原始状态。你可以把它看作一种类似 pop (请不要和 Facebook 的 Pop 框架弄混了)的行为。

### 5.2.1 效果展示

与一般使用 `UIViewAnimationOptionAutoreverse` 的动画 block 不同，因为动画设计和概念上的需要，我自己实现了将 model 值改变回原始值的过程。自定义的动画 API 的使用方法就像这样：

```objectivec
[UIView DR_popAnimationWithDuration:0.7
                         animations:^{
                                myView.transform = CGAffineTransformMakeRotation(M_PI_2);
                              }];
```

当我们完成后，效果是这个样子的 (对四个不同的 view 为位置，尺寸，颜色和旋转进行动画)：

The custom block animation API, used to animate the position, size, color, and rotation of four different views：

<img src="/images/caa/custom-block-animations.gif" alt="" style="zoom:70%;" />

### 5.2.2 代码实现

#### 1. Method Swizzle

要开始实现它，我们首先要做的是当一个 layer 属性变化时获取 delegate 的回调。因为我们无法事先预测 layer 要改变什么，所以我选择在一个 UIView 的 category 中 swizzle `actionForLayer:forKey:` 方法：

```objectivec
@implementation UIView (DR_CustomBlockAnimations)

+ (void)load
{        
    SEL originalSelector = @selector(actionForLayer:forKey:);
    SEL extendedSelector = @selector(DR_actionForLayer:forKey:);

    Method originalMethod = class_getInstanceMethod(self, originalSelector);
    Method extendedMethod = class_getInstanceMethod(self, extendedSelector);

    NSAssert(originalMethod, @"original method should exist");
    NSAssert(extendedMethod, @"exchanged method should exist");

    if(class_addMethod(self, originalSelector, method_getImplementation(extendedMethod), method_getTypeEncoding(extendedMethod))) {
        class_replaceMethod(self, extendedSelector, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod));
    } else {
        method_exchangeImplementations(originalMethod, extendedMethod);
    }
}
```

#### 2. 上下文变量控制

为了保证我们不破坏其他依赖于 `actionForLayer:forKey:` 回调的代码，我们使用一个静态变量来判断现在是不是处于我们自己定义的上下文中。对于这个例子来说一个简单的 `BOOL` 其实就够了，但是如果我们之后要写更多内容的话，上下文的话就要灵活得多了：

```objectivec
static void *DR_currentAnimationContext = NULL;
static void *DR_popAnimationContext     = &DR_popAnimationContext;

- (id<CAAction>)DR_actionForLayer:(CALayer *)layer forKey:(NSString *)event
{
    if (DR_currentAnimationContext == DR_popAnimationContext) {
        // 这里写我们自定义的代码...
    }

    // 调用原始方法
    return [self DR_actionForLayer:layer forKey:event]; // 没错，你没看错。因为它们已经被交换了
}
```

在我们的实现中，我们要确保在执行动画 block 之前设置动画的上下文，并且在执行后恢复上下文：

```objectivec
 + (void)DR_popAnimationWithDuration:(NSTimeInterval)duration
                          animations:(void (^)(void))animations
 {
     DR_currentAnimationContext = DR_popAnimationContext;
     // 执行动画 (它将触发交换后的 delegate 方法)
     animations();
     /* 一会儿再添加 */
     DR_currentAnimationContext = NULL;
 }
```

#### 3. 定义动画状态存储类

如果我们想要做的不过是添加一个从旧的值向新的值过度的动画的话，我们可以直接在 delegate 的回调中来做。然而因为我们想要更精确地控制动画，我们需要用一个帧动画来实现。帧动画需要所有的值都是已知的，而对我们的情况来说，新的值还没有被设定，因此我们也就无从知晓。

有意思的是，iOS 添加的一个基于 block 的动画 API 也遇到了同样的问题。使用和上面一样的观察手段，我们就能知道它是如何绕开这个麻烦的。对于每个关键帧，在属性变化时，view 返回 `nil`，但是却存储下需要的状态。这样就能在所有关键帧 block 执行后创建一个 `CAKeyframeAnimation` 对象。

受到这种方法的启发，我们可以创建一个小的类来存储我们创建动画时所需要的信息：什么 layer 被更改了，什么 key path 的值被改变了，以及原来的值是什么：

```objectivec
 @interface DRSavedPopAnimationState : NSObject @property (strong) CALayer  *layer; @property (copy)   NSString *keyPath; @property (strong) id        oldValue; + (instancetype)savedStateWithLayer:(CALayer *)layer                             keyPath:(NSString *)keyPath; @end @implementation DRSavedPopAnimationState + (instancetype)savedStateWithLayer:(CALayer *)layer                             keyPath:(NSString *)keyPath {     DRSavedPopAnimationState *savedState = [DRSavedPopAnimationState new];     savedState.layer    = layer;     savedState.keyPath  = keyPath;     savedState.oldValue = [layer valueForKeyPath:keyPath];     return savedState; } @end
```

接下来，在我们的交换后的 delegate 回调中，我们简单地将被变更的属性的状态存入一个静态可变数组中：

```objectivec
- (id<CAAction>)DR_actionForLayer:(CALayer *)layer forKey:(NSString *)event{    if (DR_currentAnimationContext == DR_popAnimationContext) {        // 这里写我们自定义的代码...        [[UIView DR_savedPopAnimationStates] addObject:[DRSavedPopAnimationState savedStateWithLayer:layer                                                                                 keyPath:event]];        // 没有隐式的动画 (稍后添加)        return (id<CAAction>)[NSNull null];    }    // 调用原始方法    return [self DR_actionForLayer:layer forKey:event]; // 没错，你没看错。因为它们已经被交换了}
```

#### 4. 创建关键帧动画

在动画 block 执行完毕后，所有的属性都被变更了，它们的状态也被保存了。现在，创建关键帧动画：

```objectivec
 + (void)DR_popAnimationWithDuration:(NSTimeInterval)duration
                          animations:(void (^)(void))animations
 {
     DR_currentAnimationContext = DR_popAnimationContext;

     // 执行动画 (它将触发交换后的 delegate 方法)
     animations();

     [[self DR_savedPopAnimationStates] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
         DRSavedPopAnimationState *savedState   = (DRSavedPopAnimationState *)obj;
         CALayer *layer    = savedState.layer;
         NSString *keyPath = savedState.keyPath;
         id oldValue       = savedState.oldValue;
         id newValue       = [layer valueForKeyPath:keyPath];

         CAKeyframeAnimation *anim = [CAKeyframeAnimation animationWithKeyPath:keyPath];

         CGFloat easing = 0.2;
         CAMediaTimingFunction *easeIn  = [CAMediaTimingFunction functionWithControlPoints:1.0 :0.0 :(1.0-easing) :1.0];
         CAMediaTimingFunction *easeOut = [CAMediaTimingFunction functionWithControlPoints:easing :0.0 :0.0 :1.0];

         anim.duration = duration;
         anim.keyTimes = @[@0, @(0.35), @1];
         anim.values = @[oldValue, newValue, oldValue];
         anim.timingFunctions = @[easeIn, easeOut];

         // 不带动画地返回原来的值
         [CATransaction begin];
         [CATransaction setDisableActions:YES];
         [layer setValue:oldValue forKeyPath:keyPath];
         [CATransaction commit];

         // 添加 "pop" 动画
         [layer addAnimation:anim forKey:keyPath];

     }];

     // 扫除工作 (移除所有存储的状态)
     [[self DR_savedPopAnimationStates] removeAllObjects];

     DR_currentAnimationContext = nil;
 }
```

注意老的 model 值被设到了 layer 上，所以在当动画结束和移除后，model 的值和 presentation 的值是相符合的。

创建像这样的你自己的 API 不会对每种情况都很适合，但是如果你需要在你的应用中的很多地方都做同样的动画的话，这可以帮助你写出整洁的代码，并减少重复。就算你之后从来不会使用这种方法，实际做一遍也能帮助你搞懂 UIView block 动画的 APIs，特别是你已经在 Core Animation 的舒适区的时候，这非常有助于你的提高。

## 5.3 其他的动画灵感

UIImageView 动画是一个完全不同的更高层次的动画 API 的实现方式，我会把它留给你来探索。表面上，它只不过是重新组装了一个传统的动画 API。你所要做的事情就是指定一个图片数组和一段时间，然后告诉 image view 开始动画。在抽象背后，其实是一个添加在 image view 的 layer 上的 contents 属性的离散的关键帧动画：

```objectivec
<CAKeyframeAnimation:0x8e5b020; 
    removedOnCompletion = 0; 
    delegate = <_UIImageViewExtendedStorage: 0x8e49230>; 
    duration = 2.5; 
    repeatCount = 2.14748e+09; 
    calculationMode = discrete; 
    values = (
        "<CGImage 0x8d6ce80>",
        "<CGImage 0x8d6d2d0>",
        "<CGImage 0x8d5cd30>"
    ); 
    keyPath = contents
>
```

动画 APIs 可以以很多不同形式出现，而对于你自己写的动画 API 来说，也是这样的。

# 六、总结

这一章讨论了：

- 隐式动画，还有Core Animation对指定属性选择合适的动画行为的机制。
- UIKit是如何充分利用Core Animation的隐式动画机制来强化它的显式系统，
- 以及动画是如何被默认禁用并且当需要的时候启用的。
- 最后，你了解了呈现和模型图层，以及Core Animation是如何通过它们来判断出图层当前位置以及将要到达的位置。
