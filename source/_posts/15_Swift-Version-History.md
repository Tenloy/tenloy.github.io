---
title: Swift版本更新API介绍
date: 2021-06-30 17:01:31
tags:
  - Swift-Syntax
categories:
  - Swift
---

### Swift ABI 稳定

历时5年发展，从Swift1.x发展到了Swift5.x版本，经历了多次重大改变，ABI终于稳定。

ABI 稳定就是 binary 接口稳定，意味着Swift语法基本不会再有太大的变动。也就是在运行的时候只要是用 Swift 5 (或以上) 的编译器编译出来的 binary，就可以跑在任意的 Swift 5 (或以上) 的 runtime 上。这样，我们就不需要像以往那样在 app 里放一个 Swift runtime 了，Apple 会把它弄到 iOS 和 macOS 系统里。

- Xcode 10.2 搭载的 Swift 5.0 版本的编译器

- iOS 12.2 系统预装了 Swift 5 的 runtime

## Swift 5.1

见《Swift编程从入门到精通》学习笔记

## Swift 5.2

从表面上看，Swift 5.2 在新语言特性方面绝对是一个次要版本，因为这个新版本的大部分重点是提高 Swift 底层基础设施的速度和稳定性——例如如何报告编译器错误，以及如何解决构建级别的依赖关系。

然而，虽然 Swift 5.2 的新语言特性*总数*可能相对较少，但它确实包含了几个新功能，它们可能会对 Swift 作为*函数式编程语言*的整体能力产生相当大的影响。

#### 1. callAsFunction

在 [特殊名称方法](https://swiftgg.gitbook.io/swift/yu-yan-can-kao/06_declarations#methods-with-special-names) 章节中新增了有关让类、结构体和枚举的实例作为函数调用语法糖的内容。

一些含有特殊名称的方法允许使用函数调用语法糖。如果一个类型定义了某个此类型的方法，那这些类型的实例对象都可以使用函数调用语法。这些函数调用会被解析为某个具有特殊名称的实例方法调用。

##### dynamicCallable补充

之前的 [dynamicCallable](https://swiftgg.gitbook.io/swift/yu-yan-can-kao/07_attributes#dynamicCallable) 特性中：只要定义了 `dynamicallyCall(withArguments:)` 方法或者 `dynamicallyCall(withKeywordArguments:)` 方法，一个类、结构体或者枚举类型都支持函数调用语法。

该特性用于类、结构体、枚举或协议，以将该类型的实例视为可调用的函数。该类型必须实现上面两个方法之一，或两者同时实现。

可以调用 `dynamicCallable` 特性的实例，就像是调用一个任意数量参数的函数。

```swift
@dynamicCallable
struct TelephoneExchange {
    func dynamicallyCall(withArguments phoneNumber: [Int]) {
        if phoneNumber == [4, 1, 1] {
            print("Get Swift help on forums.swift.org")
        } else {
            print("Unrecognized number")
        }
    }
}

let dial = TelephoneExchange()

// 使用动态方法调用
dial(4, 1, 1)
// 打印“Get Swift help on forums.swift.org”

dial(8, 6, 7, 5, 3, 0, 9)
// 打印“Unrecognized number”

// 直接调用底层方法
dial.dynamicallyCall(withArguments: [4, 1, 1])
```

定义了一个函数调用方法（call-as-function method）也可以达到上述效果。如果一个类型同时定义了一个函数调用方法和使用 `dynamicCallable` 属性的方法，那么在合适的情况下，编译器会优先使用函数调用方法。

函数调用方法的名称是 `callAsFunction()`，或者任意一个以 `callAsFunction(` 开头并跟随着一些已标签化或未标签化的参数——例如 `callAsFunction(_:_:)` 和 `callAsFunction(something:)` 都是合法的函数调用方法名称。

```swift
struct CallableStruct {
    var value: Int
    func callAsFunction(_ number: Int, scale: Int) {
        print(scale * (number + value))
    }
}
let callable = CallableStruct(value: 100)
callable(4, scale: 2)
callable.callAsFunction(4, scale: 2)
// 两次函数调用都会打印 208
```

#### 2. 其他

- 更新 [下标选项]() 章节，现在下标支持形参默认值。
- 更新 [自身类型]() 章节，现在 `Self` 可以在更多上下文中使用。

## Swift 5.3

#### 1. 多尾随闭包

Swift 5.3 之前即使有多个尾随闭包也只有最后一个能被写成精简的形式，这种写法一个闭包在圆括号内，另一个在外面。新的写法把这些闭包都放在圆括号外面，显得更加简洁。**注意：尾随闭包中的第一个闭包的标签会被强制省略。**

#### 2. 枚举可比较

#### 3. 异常catch多值处理

异常catch 后面可以捕获多个异常的值，以逗号隔开

```swift
catch FileReadError.FileISNull, FileReadError.FileNotFound { // 同时处理
```

#### 4. `@main`

作为声明程序的入口点，替换掉以前的`@UIApplicationMain`。

#### 5. self改变

以前闭包中引用当前范围的内容时必须带上`self.`，Swift 5.3 之后如果不产生循环引用可以省略`self.`。这个新特性对 SwiftUI 来说非常友好，因为 SwiftUI 中的 View 保存在值类型的结构体中，所以不会发生循环引用。

#### 6. didSet性能提升

以前在一个属性中使用 didSet 时，总是调用 getter 来获取该属性的 oldValue（即使没有用到），从而影响性能。Swift 5.3 之后只有在`didSet`中使用了`oldValue`参数时，getter 才会被调用。

#### 7. 语法缩进改进

guard 和 if 语句中的条件可以按列对齐。

```swift
guard let x = optionalX,
      let y = optionalY else {
}

if let x = optionalX,
   let y = optionalY {
}
```

#### 8. 新增浮点型Float16

```swift
let number: Float16 = 5.0
```

#### 9. 新增日志API

提供了 5 种级别：

- Debug：Debug时使用。
- Info：可以在排查问题时使用。
- Notice (default)：默认，可以在排查问题时使用。
- Error：在程序执行出错时使用。
- Fault：在程序出现bug时使用。

```swift
// 1.导入模块
import os

// 2.创建Logger实例
let logger = Logger()

// 3.使用log函数
logger.log(level: .debug, "test")
logger.log(level: .info, "test")
logger.log(level: .default, "test")
logger.log(level: .error, "test")
logger.log(level: .fault, "test")
```

#### 10. 其他

- Swift Package Manager 功能增强。
- Swift 语言性能继续提升。

## Swift 5.4

#### 1. 改进隐式成员语法

在 UIKit 和 SwiftUI 中设置颜色时，无法直接通过`.`的方式进行颜色的书写，必须带上前缀`UIColor`或者`Color`，因为无法根据上下文进行成员推测，Swift 5.4 中改进了这个语法，可以省去前缀且支持链式调用。

- UIKit

```swift
let view = UIView()
view.backgroundColor = .red.withAlphaComponent(0.5)
```

- SwiftUI

```swift
struct ContentView: View {
    var body: some View {
        Text("Swift 5.4")
            .foregroundColor(.red.opacity(0.5))
            .padding()
    }
}
```

#### 2. 支持多个可变参数

Swift 5.4 之前函数只能有一个参数为可变参数， 现在支持多个可变参数。

```swift
// 多个可变参数
func score(courses: String..., scores: Int...) {
    for i in 0 ..< courses.count {
        print("《\(courses[i])》课程的成绩：\(scores[i])")
    }
}

// 调用
score(courses: "Swift", "iOS开发", "SwiftUI", scores: 90, 95, 100)
```

#### 3. 嵌套函数支持重载

Swift 5.4 之前普通函数可以重载，现在嵌套函数也支持重载。

```swift
func method() {
    // 内嵌函数一
    func add(num1: Int, num2: Int) -> Int {
        num1 + num2
    }
    // 内嵌函数二
    func add(num1: Int, num2: Int, num3: Int) -> Int {
        num1 + num2 + num3
    }
    // 内嵌函数三
    func add(num1: Double, num2: Double) -> Double {
        num1 + num2
    }
    // 内嵌函数四
    func add(a num1: Int, b num2: Int) -> Int {
        num1 + num2
    }

    add(num1: 10, num2: 20) // 30
    add(num1: 10, num2: 20, num3: 30) // 60
    add(num1: 10.0, num2: 20.0) // 30
    add(a: 10, b: 20) // 30
}

method()
```

#### 4. Result builders

- Swift 5.4 之前叫 **Function builders**，它使用一个`buildBlock`方法可以将**多个内容**构建为**一个结果**，该特性在 SwiftUI 广泛使用。
- 可以使用`@resultBuilder`自定义 Result builders。

```swift
@resultBuilder
struct StringBuilder {
    // buildBlock中将多个值构建为一个结果
    static func buildBlock(_ strs: String...) -> String {
        // 以换行符拼接多个字符串
        strs.joined(separator: "\n")
    }

    // if逻辑分支
    static func buildEither(first component: String) -> String {
        return "if \(component)"
    }

    // else逻辑分支
    static func buildEither(second component: String) -> String {
        return "else \(component)"
    }
}

@StringBuilder
func buildString() -> String {
    "静夜思"
    "唐•李白"
    "床前明月光，疑是地上霜。"
    "举头望明月，低头思故乡。"

    if Bool.random() {
        "一首诗"
    } else {
        "一首词"
    }
}

print(buildString())
```

#### 5. 局部变量支持属性包装

Swift 5.4 将 Swift 5.1 中引入的属性包装支持到局部变量。

```swift
// 属性包装
@propertyWrapper struct Trimmed {
    private var value: String = ""

    var wrappedValue: String {
        get { value }
        set { value = newValue.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    init(wrappedValue initialValue: String) {
        wrappedValue = initialValue
    }
}

struct Post {
    func trimed() {
        // 局部变量
        @Trimmed var content: String = "  Swift 5.4 Property Wrappers  "
        print(content)
    }
}

class ViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let post = Post()
        post.trimed()
    }
}
```

- SwiftUI 中的应用。

```swift
// 自定义View
struct CustomView<Content: View>: View {
    // 属性包装定义内容
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView(.horizontal) {
            HStack(content: content)
                .padding()
        }
    }
}

struct ContentView: View {
    var body: some View {
        CustomView {
            ForEach(0 ..< 10) { _ in
                Image(systemName: "heart")

                Text("SwiftUI")
            }
        }
    }
}
```

## Swift 5.5

在 [WWDC21](https://developer.apple.com/videos/) 上，Apple 推出了Swift 5.5第一个快照版本

#### 1. Async/Await

在众多新功能中，最令人期待的功能之一是使用和 actor[更好地支持并发](https://developer.apple.com/documentation/swift/swift_standard_library/concurrency)`aysnc/await`。

#### 2. throwing properties

[What's new in Swift 5.5? — hackingwithswift](https://www.hackingwithswift.com/articles/233/whats-new-in-swift-5-5)



## 参考文档

- https://swift.org/blog/
- [Swift版本历史记录—SwiftGG](https://swiftgg.gitbook.io/swift/huan-ying-shi-yong-swift/04_revision_history)
- [Hacking With Swift](https://www.hackingwithswift.com/articles)、[Swift By Sundell](https://www.swiftbysundell.com/articles/)这是两个个人网站，可以在文章中搜5.4 5.5等查看
- [Swift 5.3 新特性 — YungFan](https://juejin.cn/post/6913699890472648712)
- [Swift 5.4 新特性 — YungFan](https://juejin.cn/post/6961964537197101064)