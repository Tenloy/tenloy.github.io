---
title: Objective-C — 内存管理
date: 2020-08-24 09:37:02
urlname: oc-memory-manage.html
tags:
categories:
  - iOS
---

# 一、原则与实现手段

## 1.1 原则

- 自己生成的对象，自己所持有
- 非自己所生成的对象，自己也能持有
- 自己持有的对象自己释放
- 非自己持有的对象无法释放

## 1.2 核心

**内存管理的核心即是引用计数，散列表管理**。

**实现的管理手段可以分为：手动管理、自动释放池**。

- MRC下的实现
  - 手动release、retain、autorelease
- ARC下的实现（**ARC式的内存管理是编译器的工作，且需要Objective-C运行时库的协助。**）
  - 本质上是相同的，只是在源代码的书写方法上稍有不同，引入了所有权修饰符，来协助完成内存管理工作
  - `__strong`
  - `__weak`
  - `__unsafe_unretained`
  - `__autoreleasing`

# 二、内存管理相关的几个C函数

内存区域可以分为栈，堆，可读写区(全部变量与静态变量)和只读区(常量与代码段)。局部变量，函数形参，临时变量都是在栈上获得内存的，它们获取的方式都是由编译器自动执行的。

C 标准函数库提供了许多函数来实现对堆上内存管理，其中包括：`malloc` 函数，`free` 函数，`calloc` 函数和`realloc` 函数。使用这些函数需要包含头文件 `stdlib.h`。

## 2.1 malloc(n)

malloc函数可以从堆上获得指定字节的内存空间，其函数声明如下：

```cpp
/*
 * @param n 要求分配的字节数
 * @return  如果函数执行成功，malloc返回获得内存空间的首地址；如果函数执行失败，那么返回值为NULL
 */
void * malloc(int n);
```

由于malloc函数值的类型为void型指针，因此，可以将其值类型转换后赋给任意类型指针，这样就可以通过操作该类型指针来操作从堆上获得的内存空间。

需要注意的是：malloc函数分配得到的内存空间是未初始化的。因此，一般在使用该内存空间时，必须要调用另一个函数memset来将其初始化为全0。

## 2.2 memeset(p, c, n)

memset函数可以将指定的内存空间按字节单位置为指定的字符.

memset函数的声明如下：

```cpp
/*
 * @param p 要清零的内存空间的首地址
 * @param c 要设定的值
 * @param n 被操作的内存空间的字节长度
 * @return  如果函数执行成功，malloc返回获得内存空间的首地址；如果函数执行失败，那么返回值为NULL
 */
  void * memset (void * p,int c,int n) ;
```

如果要用memset清0，变量c实参要为0。malloc函数和memset函数的操作语句一般如下：

```c
int * p = NULL;
p = (int *)malloc(sizeof(int));
if(p == NULL) 
  printf("Can’t get memory!\n");
memset(p, 0, siezeof(int));
```

## 2.3 free(p)

从堆上获得的内存空间在程序结束以后，系统不会将其自动释放，需要程序员来自己管理。一个程序结束时，必须保证所有从堆上获得的内存空间已被安全释放，否则，会导致内存泄露。

free函数可以实现释放内存的功能。

```cpp
/*
 * @param p 要释放的void类型指针
 * @return  如果函数执行成功，mall
 */
void free (void * p);
```

free函数只是释放指针指向的内容，而该指针仍然指向原来指向的地方，此时，指针为野指针，如果此时操作该指针会导致不可预期的错误。安全做法是：在使用free函数释放指针指向的空间之后，将指针的值置为NULL。

```c
free(p);
p = NULL;
```

注意：使用malloc函数分配的堆空间在程序结束之前必须释放。

## 2.4 calloc(n, size)

calloc函数的功能与malloc函数的功能相似，都是从堆分配内存。

```cpp
/*
 * @param n  分配多少个
 * @param size 要求分配的单位字节数
 * @return  函数返回值为void型指针。如果执行成功，函数从堆上获得size X n的字节空间，并返回该空间的首地址。如果执行失败，函数返回NULL。
 */
void *calloc(int n,int size);
```

该函数与malloc函数的一个显著不同是：

- calloc函数得到的内存空间是经过初始化的，其内容全为0。
- calloc函数适合为数组申请空间，可以将size设置为数组元素的空间长度，将n设置为数组的容量。

提示：calloc函数的分配的内存也需要自行释放。

## 2.5 realloc()

realloc函数的功能比malloc函数和calloc函数的功能更为丰富，可以实现内存分配和内存释放的功能。

```cpp
/*
 * @param p 必须为指向堆内存空间的指针，即由malloc函数、calloc函数或realloc函数分配空间的指针
 * @param n 内存块大小
 * @return  首地址
 */
void * realloc(void * p, int n);
```

realloc函数将指针p指向的内存块的大小改变为n字节。

- 如果n小于或等于p之前指向的空间大小，那么。保持原有状态不变。
- 如果n大于原来p之前指向的空间大小，那么，系统将重新为p从堆上分配一块大小为n的内存空间，同时，将原来指向空间的内容依次复制到新的内存空间上。p之前指向的空间被释放。

注意：

1. relloc函数分配的空间也是未初始化的， 如果要使用realloc函数分配的内存，也是必须使用memset函数对其内存初始化。
2. 如realloc函数重新分配的内存地址，有时候会改变，有时候不会改变

注意：使用malloc函数，calloc函数和realloc函数分配的内存空间都要使用free函数或指针参数为NULL的realloc函数来释放。

# 三、ARC 规则

## 3.1 ARC下的代码编写规则

在 ARC 有效的情况下，源码编写必须遵循一定的规则。

### 3.1.1 构造方法的命名规则

须遵守内存管理的构造方法命名规则(MRC下最好也遵循)：

- 在MRC下：用于对象生成/持有的方法必须遵守以下的命名规则：方法名以`alloc/new/copy/mutableCopy`开头
- 在ARC下：增加一条：`init`，且更为严格：
  - 必须是实例方法，并且必须要返回对象。
  - 返回的对象应为id类型或该方法声明类的对象类型，抑或是超类或子类。
  - 返回的对象不注册autoreleasepool中。

### 3.1.2 不能显式调用内存管理相关方法

ARC下，内存管理是编译器的工作，没有必要再使用内存管理的方法(retain/release/retainCount/autorelease)。

### 3.1.3 不能使用NSAllocateObject/NSDeallocateObject

### 3.1.4 不能使用区域（NSZone）

无论是否是ARC，NSZone在iOS 5 之后，就已经被忽略到了，即使使用，也不会生效。

### 3.1.5 不能显式调用dealloc

无论是ARC/MRC，只要对象被废弃，都会自动调用这个函数，进而调用`free`函数释放对象

### 3.1.6 使用@autoreleasepool块替代NSAutoreleasePool

### 3.1.7 对象不能作为C语言结构体(struct/union)的成员

**原因：**

- ARC下的内存管理其实是编译器的工作，所以编译器必须能够知道并管理对象的生存周期。
- 对于C语言来说，自动变量(局部变量)可以使用该变量的作用域来管理对象，但是C语言的规约上，并没有方法来管理结构体成员的生存周期！

**解决方案：**

- 将对象型变量强制转换为 `void *`。
- 附加 `__unsafe_unretained` 修饰符( `__unsafe_unretained` 修饰符的变量是不属于编译器的内存管理对象范围)，但是需要注意内存泄漏或野指针的问题。

### 3.1.8 显式转换id 和 void *

可以认为id = void *，都是用于隐藏对象类型的类名部分

接下来的转换，与其说是id 和 void * 转换，不如说是Foundation与Core Foundation对象转换

### 3.8.1 `__bridge`

```objectivec
void *p = (__bridge void *)obj;  
```

但是其安全性与 `__unsafe_unretained` 来修饰对象类变量差不多，甚至比后者更低，极有可能造成野指针。

```objc
id obj = (__bridge id)p;
```

### 3.8.2 `__bridge_transfer` 与 `__bridge_retained`

```objc
Objective-C变量 = (__bridge_transfer <#Objective-C type#>)CF变量
```

理解：

1. 被转换的CF变量在该变量被赋值给 转换目标变量 后随之被释放。
2. 然后目标变量即OC对象就接着由Foundation框架的方法来进行管理：MRC、ARC

```objc
CF变量  = (__bridge_retained <#CF type#>)Objective-C变量
```

理解：

1. 使CF变量持有被赋值的OC变量    
2. 既然持有了，那也就需要释放，可以使用 `__bridge_transfer` 来释放：`(void)(__bridge_transfer id)p;` 

也可以使用另外两个封装的函数来实现：

```objectivec
CFTypeRef CFBridgingRetain(id X) {
  return (__bridge_retained CFTypeRef)X;
}

id CFBridgingRelease(CFTypeRef X) {
    return (__bridge_transfer id)X; 
}
```

CoreFoundation与Foundation对象没有区别，所以简单的转换即可实现，另外，这种转换不需要使用额外的CPU资源，因此也被称为**免费桥**。

## 3.2 @property声明属性，内存管理关键字

ARC下，用@property声明属性时，一些关键字与所有权修饰符的对应关系：

| 属性声明的属性    | 所有权修饰符                                 |
| ----------------- | -------------------------------------------- |
| assign            | __unsafe_retained修饰符                      |
| copy              | __strong修饰符（但是被赋值的是被复制的对象） |
| retain            | __strong修饰符                               |
| strong            | __strong修饰符                               |
| unsafe_unretained | __unsafe_retained修饰符                      |
| weak              | __weak                                       |

## 3.3 静态数组与动态数组在内存管理上的差异

静态数组即长度固定的数组。
- 创建在栈区，由编译器负责内存的申请和释放。
- `__strong`/`__weak`/`__autoreleasing` 修饰符修饰的静态数组，能保证其初始化为nil
- **静态数组在超出其变量作用域时**，随着数组变量的强引用消失，**数组中的各个变量也会失去一个强引用**，如果引用计数此时为0，那么就会被释放。

```objc
{
    id objs[2];
    objs[0] = [[NSObject alloc] init];
    objs[1] = [NSMutableArray array];
}
```

动态数组即长度不固定的数组。
- 创建在堆区，手动管理内存。
- 动态数组，**需要手动释放所有的元素**。因为动态数组是由开发者管理内存，编译器不能确定动态数组的生存周期，所以不能自动插入释放赋值对象的代码。

```objc
// 声明动态数组用指针
id __strong *array = nil;  

// 如前所述，由于“id* 类型”默认为“id __autoreleasing *类型”，所以有必要显式指定为__strong修饰符。另外，虽然保证了附有__strong修饰符的id型变量被初始化为nil，但并不保证附有__strong修饰符的id指针型变量被初始化为nil.

array = (id __strong *)malloc(sizeof(id) * entries);
for (NSUInteger i = 0; i < entries; ++i)
    array[i] = nil;

array[0] = [[NSObject alloc] init];
...

// 需要手动释放所有元素
for (NSUInteger i = 0; i < entries; ++i)
    array[i] = nil;
free(array);
```

# 四、ARC 实现

## 4.1 __strong的实现

### 4.1.1 对象的生成类型

从**内存管理的方法命名规则**的角度上将__strong对象的创建生成方式分为两种，分析其运行过程：

第一种：自己创建并持有

```objectivec
id __strong obj = [[NSArray alloc] init]; 

/* 编译器的模拟代码*/
id obj = obje msqSend (NSObject, @selector (alloc));
objc_msgSend (obj, @selector (init));
obic_release (obj);
```

第二种：非自己创建并持有，这种初始化方式，秉着谁创建谁释放的原则，返回值需要是一个autorelease对象才能配合调用方正确管理内存

```objectivec
id __strong obj = [NSArray array]; 

/* 编译器的模拟代码*/
id obj = objc_msgSend (NSMutableArray, @selector (array)); //返回一个autorelease对象
objc_retainAutoreleasedReturnValue (obj); //参数，应为autorelease对象。

// 那么array方法中到底做了什么，返回了一个autorelease对象
+ (id) array {
  id obj = objc_msgSend (NSMutableArray, @selector (alloc));
  objc_msgsend (objc, @selector(init));
  return objc_autoreleaseReturnValue (obj);
}
```

要点：

- **内存管理方法命名规则规定：alloc/new/copy/mutableCopy开头之外的初始化方法需要返回autorelease对象**
- `objc_retainAutoreleasedReturnValue` 与 `objc_autoreleaseReturnValue` **是成对出现的，用于alloc/new/copy/mutableCopy方法以外的初始化构造方法返回对象的实现上。**
- id类型与对象类型默认是__strong修饰符。

### 4.1.2 objc_autoreleaseReturnValue

两个函数的实现可以在 Objective-C [NSObject.mm](https://opensource.apple.com/source/objc4/objc4-723/runtime/NSObject.mm.auto.html) 的源码中找到：

```cpp
//加工过的代码
id objc_autoreleaseReturnValue(id obj) {
    if (callerAcceptsOptimizedReturn(__builtin_return_address(0))) {
        if (ReturnAtPlus1){
            tls_set_direct(RETURN_DISPOSITION_KEY, (void*)(uintptr_t)ReturnAtPlus1);
        }
        return obj;
    }   
    return objc_autorelease(obj);
}
```

`callerAcceptsOptimizedReturn(__builtin_return_address(0))` 函数在不同架构的 CPU 上实现也是不一样的。具体代码不再贴出来了。

主要作用：

1. `__builtin_return_address(0)` 获取当前函数返回地址。
2. callerAcceptsOptimizedReturn() 方法判断调用方是否紧接着调用了 objc_retainAutoreleasedReturnValue或者 objc_unsafeClaimAutoreleasedReturnValue方法。
3. 如果调用了objc_retainAutoreleasedReturnValue，就表示外面是ARC环境，那么就可以使用TLS了，否则MRC就不能使用。

### 4.1.3 objc_retainAutoreleasedReturnValue

```objc
id objc_retainAutoreleasedReturnValue(id obj) {
    ReturnDisposition disposition = (ReturnDisposition)(uintptr_t)tls_get_direct(RETURN_DISPOSITION_KEY);
    if (disposition == ReturnAtPlus1) return obj;
    return objc_retain(obj);
}
```

### 4.1.4 补充说明

- `objc_autoreleaseReturnValue` 函数同 `objc_autorelease` 函数不同，一般不仅限于注册对象到autoreleasepool中。
- 在ARC中原本对象生成之后是要注册到autoreleasepool中。但是此时调用了`objc_autoreleaseReturnValue`函数，该函数就会检查使用该函数的方法或函数调用方的执行命令列表，如果方法或函数的调用方在调用了方法或函数后紧接着调用`objc_retainAutoreleasedReturnValue()`函数(调用了这个方法就表示外面的环境是ARC)，就将这个返回值obj储存在TLS中，然后直接返回这个obj（不调用autorelease）给方法或者函数的调用方。达到了即使对象不注册到autoreleasepool中，也可以返回拿到相应的对象。
- 同时，在外部接收这个返回值的objc_retainAutoreleasedReturnValue里，发现TLS中正好存了这个对象，那么直接返回这个object（不调用retain）。

> TLS 全称为 Thread Local Storage（线程本地存储），是每个线程专有的键值存储，需要调用方与被调用方必须都是ARC的情况下（即全ARC环境下）

**通过`objc_autoreleaseReturnValue`函数和`objc_retainAutoreleasedReturnValue`函数的协作，利用TLS做中转，可以不将对象注册到autoreleasepool中而直接传递，免去了对返回值的内存管理，实现过程最优化。**

> 总结：
>
> MRC下：对象需要经历方法内部new->内部autorelease->外部retain->外部release这样四步流程
>
> ARC下：对象需要经历方法内部new->外部release两步，省了中间两步“autorelease->retain”（TLS优化其实与OC内存管理“谁生成谁销毁谁持有谁释放”的黄金法则有所违背）

## 4.2 __weak的实现

### 4.2.1 要点

- 不持有新值，不释放旧值
- 在持有某对象的弱引用时，当对象被废弃，弱引用自动失效，且置为nil
- __weak修饰符的变量不能直接指向，没有强引用的、刚初始化完成的对象，因为没形成强引用，当即就会释放，所以会报警告。
- `__weak` 修饰符只能用于iOS5以上以及OS X Lion以上的版本，在iOS 4以及OS X Snow Leopard的应用程序中可使用 `__unsafe_unretained` 修饰符来代替，有时在其他环境下也不能使用。

### 4.2.2 `objc_initWeak` 与 `objc_destroyWeak` 

下面通过一些代码来解析实现过程，注意，__weak是在objc ARC下编译的，所以转换成C++代码的时候，需要加一些指定环境。

```bash
clang -rewrite-objc -fobjc-arc -stdlib=libc++ -mmacosx-version-min=10.7 -fobjc-runtime=macosx-10.7 -Wno-deprecated-declarations test.m
```

```objectivec
{
    id __weak obj1 = obj;   
}

/*编译器的模拟代码*/
id obj1;
objc_initWeak (&obj1, obj); //通过objc-initWeak函数初始化附有__weak修饰符的变量
objc_destroyWeak (&obj1);//在变量作用域结束时通过objc_destroyWeak函数释放该变量.
```

源码实现：

```objectivec
// objc_initWeak 函数将附有 __weak 修饰符的变量初始化为0后，会将赋值的对象作为参数调用 objc_storeWeak 函数。 == objc_storeWeak (&obj1, obj);
id objc_initWeak(id *location, id newObj) {
    if (!newObj) {
        *location = nil;
        return nil;
    }
    return storeWeak(location, (objc_object*)newObj);
}

// objc_destroyWeak 函数将 0 作为参数调用 objc_storeWeak 函数。 == objc_storeWeak(&obj1, 0);
void objc_destroyWeak(id *location) {
    (void)storeWeak(location, nil);
}
```

即前面的源代码与下列源代码相同。

```objectivec
/*编译器的模拟代码*/
id obj1;
obj1 = 0;

objc_storeWeak (&obj1, obj);
objc_storeWeak (&obj1, 0);
```

### 4.2.3 objc_storeWeak

`objc_storeWeak` 函数：

- 把第二参数的赋值对象的地址作为 **键值**。把第一参数的附有__weak修饰符的变量的地址注册到weak表中。
- 如果第二参数为0，则把变量的地址从**weak表**中删除。并从**引用计数表**中删除对应的键值记录。

**weak表与引用计数表相同，作为散列表被实现**。如果使用weak表，将废弃对象的地址作为键值进行检索，就能高速地获取对应的附有__weak修饰符的变量的地址。另外，由于一个对象可同时赋值给多个附有 weak修饰符的变量中，所以对于**一个键值，可注册多个变量的地址**。

### 4.2.4 释放对象的过程

```objc
(1) objc_release
(2) 因为引用计数为0所以执行dealloc
(3) _objc_rootDealloc
(4) obiect_dispose
(5) objc_destructInstance
(6) objc_clear_deallocating.
```

对象被废弃时最后调用的objc_clear_deallocating函数的动作如下:

1. 从weak表中获取废弃对象的地址为键值的记录。
2. 将包含在记录中的所有附有__weak修饰符变量的地址,赋值为nil.
3. 从weak表中删除该记录。
4. 从引用计数表中删除废弃对象的地址为键值的记录。

以上即是，__weak修饰符的变量所引用的对象被废弃时，被赋值为nil的过程。

由以上也可知道，如果大量便用附有 `__weak` 修饰符的变量,则会消耗相应的CPU资源。良策是只在避免循环引用的时候使用 `__weak`。

### 4.2.5 `__weak` 变量会被注册到 autoreleasepool

**若使用附有` __weak` 修饰符的变量，即是使用注册到autoreleasepool中的对象**。

```objc
{
    id __weak obj1 = obj;
    NSLog(@"%@", obj1);
}
```

该源代码可转换为如下形式：

```objc
/* 编译器的模拟代码 */
id obj1;
objc_initweak(&obj1, obj);
id tmp = objc_loadweakRetained(&obj1);
objc_autorelease(tmp);
NSLog(@"%@", tmp);
objc_destroyweak(&obj1);
```

与被赋值时相比，在使用附有`__weak` 修饰符变量的情形下，增加了对 `objc_loadWeakRetained`
函数和 `objc_autorelease` 函数的调用。这些函数的动作如下：

- `objc_loadWeakRetained` 函数取出附有 `__weak` 修饰符变量所引用的对象并 retain。
- `objc_autorelease` 两数将对象注册到 autorelcasepool 中。

由此可知，因为附有 `__weak` 修饰符变量所引用的对象像这样被注册到autoreleasepool 中，
所以在 @autoreleasepool 块结束之前都可以放心使用。但是，如果大量地使用附有 `__weak` 修饰
符的变量，注册到autoreleasepool 的对象也会大量地增加，因此在使用附有 `__weak` 修饰符的变
量时，最好先暂时赋值给附有 `__strong` 修饰符的变量后再使用。

比如，以下源代码使用了5次附有 weak 修饰符的变量o。

```objc
{
    id __weak o = obj:
    NSLog(@"1 %@", o);
    NSLog(@"2 %@", o);
    NSLog(@"3 %@", o);
    NSLog(@"4 %@", o);
    NSLog(@"5 %@", o);
}
```

相应地，变量 o 所赋值的对象也就注册到autoreleasepool 中5次。

```
objc[14481]: ##############
objc[14481]: AUTORELEASE POOLS for thread 0xad0892c0
objc[14481]: 6 releases pending.
objc[14481]: [0x6a85000]  ................  PAGE  (hot) (cold)
objc[14481]: [0x6a85028]  ################  POOL 0x6a85028
objc[14481]: [0x6a8502c]         0x6719e40  NSObject
objc[14481]: [0x6a85030]         0x6719e40  NSObject
objc[14481]: [0x6a85034]         0x6719e40  NSObject
objc[14481]: [0x6a85038]         0x6719e40  NSObject
objc[14481]: [0x6a8503c]         0x6719e40  NSObject
objc[14481]: ##############
```

将附有`__weak` 修饰符的变量 o 赋值给附有 `__strong` 修饰符的变量后再使用可以避免此类问题。

```objc
{
    id __weak o = obj;
    id tmp = o;
    NSLog(@"1 %@", tmp);
    NSLog(@"2 %@", tmp);
    NSLog(@"3 %@", tmp);
    NSLog(@"4 %@", tmp);
    NSLog(@"5 %@", tmp);
}
```

在 “tmp = o;” 时对象仅注册到autoreleasepool 中 1 次。

### 4.2.6 不能使用__weak修饰符的场景

- 在iOS4 和OS X Snow Leopard 中是不能使用 `__weak` 修饰符的，而有时在其他环境下也不能使用。

- 实际上存在着不支持 `__weak` 修饰符的类。

  - 独自实现引用计数机制的类。例如NSMachPort类，这些类重写了retain/release并实现该类独自的引用计数机制。因为赋值以及使用附有 `__weak` 修饰符的变量都必须恰当地使用objc4运行时库中的函数，所以这些独自实现引用计数机制的类大多不支持 `__weak` 修饰符。

  - 声明中附加了`__attribute__ ((objc_arc_weak_reference_unavailable))`这一属性的类，同时定义了NS_AUTOMATED_REFCOUNT_WEAK_UNAVAILABLE。

  - 如果将不支持 `__weak` 声明类的对象赋值给附有 `__weak` 修饰符的变量，那么一旦编译器检验出来就会报告**编译错误**。而且在Cocoa框架类中，不支持 `__weak` 修饰符的类极为罕见，因此没有必要太过担心。

  - allowsWeakReference/retainWeakReference实例方法（没有写入NSObject接口说明文档中）返回NO的类。这些方法的声明如下：

    ```objc
    - (BOOL)allowsWeakReference;
    - (BOOL)retainWeakReference;
    ```

在赋值给 `__weak` 修饰符的变量时，

- 如果赋值对象的allowsWeakReference方法返回NO，程序将异常终止。

  ```
  cannot form weak reference to instance (0x753e180) of class MyObject
  ```

- 被赋值对象的retainWeakReference方法返回NO的情况下，该变量将使用“nil”。如以下的源代码：

  ```objc
  @implementation MyObject
  - (BOOL)retainWeakReference{
      return NO;
  }
  @end
    
  {
      id __strong obj = [[MyObject alloc] init];
      id __weak o = obj;
      NSLog(@"%@", o); //正常来讲，o指向的是一个存在强引用的对象，此处应该有值。但由于retainWeakReference return NO，所以此处打印为 (null)
  }
  ```

## 4.3 __unsafe_unretained

- `__unsafe_unretained` 是不安全的所有权修饰符，ARC式的内存管理是编译器的工作，但附有__unsafe_unretained修饰符的变量不属于编译器的内存管理对象。
- 其与 `__weak` 一样都是弱引用，区别在于 `__weak` 对象在释放的时候，对象或者指针会被置为nil，但是`__unsafe_unretained` 不会，会造成野指针。

## 4.4 __autoreleasing与Autorelease Pool

### 4.4.1 什么是自动释放池

自动释放，也是延迟释放。

自动释放池的实现原理或者说作用：在自动释放池被销毁或耗尽时，会向池中的所有对象发送release消息，释放所有autorelease对象。

### 4.4.2 AutoreleasePool的使用

```objectivec
//MRC下
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    id obj = [[NSObject alloc] init];
    [obj autorelease];
    [pool drain];   //相当于[obj release];

//ARC下
    @autoreleasepool{
        NSArray __autorelasing * arr = [[NSArray alloc] init];
        // 或者
        NSArray * arr = [NSArray arrayWithObject:@""]; // alloc/new/copy/mutableCopy之外的方法，生成的对象，默认是自动释放池管理(MRC与ARC下)
    }
```

### 4.4.3 AutoreleasePool的实现原理

#### 1. AutoreleasePoolPage类介绍

NSAutoreleasePool对应的AutoreleasePoolPage类。

ARC下，我们使用@autoreleasepool{}来使用一个AutoreleasePool，随后`clang -rewrite-objc`可编译成下面代码：

```objectivec
//被编译的代码
#import <Foundation/Foundation.h>
int main(int argc, const char * argv[])
{
    @autoreleasepool{
        id obj = [[NSObject alloc] init];
    }
    return 0;
}

extern "C" __declspec(dllimport) void * objc_autoreleasePoolPush(void);
extern "C" __declspec(dllimport) void objc_autoreleasePoolPop(void *);
struct __AtAutoreleasePool {
  __AtAutoreleasePool() {atautoreleasepoolobj = objc_autoreleasePoolPush();}
  ~__AtAutoreleasePool() {objc_autoreleasePoolPop(atautoreleasepoolobj);}
  void * atautoreleasepoolobj;
};

//略作改动，对应MRC下的代码
NSAutoreleasePool *pool=[[NSAutoreleasePool alloc) init]; /* 等同于objc_autoreleasePoolPush() */
id obj = [[NSObject alloc) init];
[obj autorelease];     /* 等同于objc_autorelease(obj) */
[pool drain];          /* 等同于objc_autoreleasePoolPop(pool) */
```

而这几个函数都是对AutoreleasePoolPage的简单封装，所以**自动释放机制的核心就在于这个类**。

**可通过objc4库的runtime/objc-arr.mm来确认苹果中autorelease的实现。**

objo4/runtime/objc-arr.mm class AutoreleasePoolPage:

```cpp
class AutoreleasePoolPage
{
    static inline void *push (){  //相当于生成或持有NSAutoreleasePool类对象; 
    }
    static inline void *pop (void *token){  //相当于废弃NSAutoreleasePool类对象; 
        releaseAll(); 
    }
    static inline id autorelease(id obj){  //相当于NSAutoreleasePoo1类的addobject类方法
        AutoreleasePoolPage *autoreleasePoolPage = /* 取得正在使用的AutoreleasePoolPage实例 */;
        autoreleasePoolPage->add(obj);
    }
    id *add (id obj){   // 将对象追加到内部数组中;
    }
    void releaseAll (){ // 调用内部数组中对象的release实例方法;
    }
};

void *objc autoreleasePoolPush (void){
    return AutoreleasePoolPage: :push ();
}
void objc autoreleasePoolPop (void *ctxt){
    AutoreleasePoolPage: :pop (ctxt);
}
id *objc autorelease (id obj){
    return AutoreleasePoolPage: :autorelease (obj);
}
```

#### 2. AutoreleasePoolPage类的结构

AutoreleasePoolPage是一个C++实现的类

<img src="/images/ios/autorelp/01.webp" style="zoom:90%;" />

- AutoreleasePool并没有单独的结构，而是由若干个`AutoreleasePoolPage` 作为结点以**双向链表**的形式组合而成，**会在一个Page空间占满时进行增加，objc_autoreleasePoolPop(哨兵对象)的时候进行删除**。
- AutoreleasePoolPage每个对象会开辟4096字节内存（也就是虚拟内存一页的大小），除了上面的实例变量所占空间，剩下的空间全部用来储存autorelease对象的地址、以及哨兵对象的地址（*见下文释放时机部分*）。

参数解读：

- parent 指向父结点，第一个结点的 parent 值为 nil ；
- child 指向子结点，最后一个结点的 child 值为 nil ；
- thread指针指向当前线程，每个AutoreleasePool只对应一个线程
- `id *next`指针作为游标指向栈顶最新add进来的autorelease对象的下一个位置，初始化时指向begin();
- magic 用来校验 AutoreleasePoolPage 的结构是否完整
- depth 代表深度，从 0 开始，往后递增 1；

AutoreleasePoolPage 的存储结构：

<img src="/images/ios/autorelp/02.webp" style="zoom:90%;" />

一个AutoreleasePoolPage的空间被占满时(next == end()时)，会新建一个AutoreleasePoolPage对象，连接链表，后来的autorelease对象在新的page加入。

#### 3. 释放机制

**每当**进行一次 `objc_autoreleasePoolPush` 调用时，runtime就向当前的AutoreleasePoolPage中add进一个**哨兵对象**，值为0（也就是个nil），那么这一个page就变成了下面的样子：

<img src="/images/ios/autorelp/03.webp" style="zoom:90%;" />

`objc_autoreleasePoolPush `的返回值正是这个哨兵对象的地址，被 `objc_autoreleasePoolPop(哨兵对象) `作为入参，于是：

1. 根据传入的哨兵对象地址找到哨兵对象所处的page
2. 在当前page中，将晚于哨兵对象插入的所有autorelease对象都发送一次`-release`消息，并向回移动`next`指针到正确位置
3. 补充2：从最新加入的对象一直向前清理，可以向前跨越若干个page，直到哨兵所在的page

#### 4. 嵌套的AutoreleasePool

pop的时候总会释放到上次push的位置(**上次push时返回的哨兵对象地址**)为止，多层的pool就是多个哨兵对象而已，互不影响。

### 4.4.4 __autoreleasing所有权修饰符

> ARC有效时，用@autoreleasepool块替代NSAutoreleasePool类，用附有__autoreleasing修饰符的变量替代autorelease方法

- **id的指针或对象的指针**在没有显示指定时会被附加上__autoreleasing修饰符，**赋值给对象指针时，所有权修饰符必须一致**。
- 只能自动变量，才可以显式指定__autoreleasing修饰符(包括局部变量、函数、方法参数)。

### 4.4.5 加入自动释放池的几种方法

- 调用autorelease的对象(MRC下)、用__autoreleasing修饰的对象(ARC下)
- 用alloc/new/copy/mutableCopy之外的方法，生成的对象，默认是自动释放池管理(MRC与ARC下)
  ```objc
  NSArray * array = [NSArray arrayWithCapacity: 1];
  // 等同于
  NSArray * array = [[[NSArray alloc] initWithCapacity:1] autorelease];
  ```
- `__weak` 的变量指向一个 `__strong` 的对象，每次使用这个变量的时候，都会把这个变量加入到自动释放池中一次(ARC下)。
  - 因为 `__weak` 修饰符只持有对象的弱引用，而且在访问引用对象的过程中，该对象可能被废弃。如果把要访问的对象注册到autoreleasepool中，那么在@autoreleasepool块结束之前都能确保对象的存在。

### 4.4.6 打印自动释放池中的对象

可通过 NSAutoreleasePool 类中的调试用非公开类方法 `showPools` 来确认已被autorelease的对象的状况。showPools会将现在的NSAutoreleasePool的状况输出到控制台。

```objc
[NSAutoreleasePool showPools];  
```

或者直接使用 `_objc_autoreleasePoolPrint()` 函数来打印(**无论ARC是否有效**)。

```cpp
/* 函数声明 */
extern _objc_autoreleasePoolPrint();

/* 调用 */
_objc_autoreleasePoolPrint();
```

### 4.4.7 自动释放池的释放时机

#### 1. 主线程中

主线程中的最外层@autoreleasepool {} ：

runloop默认开启，每一次运行循环开始，也就是每当事件被触发时都会创建自动释放池。运行循环结束前会释放自动释放池，还有池子满了也会销毁。（**无论ARC是否有效，NSRunloop都能随时释放注册到autoreleasepool中的对象**）。

#### 2. 子线程中

子线程中的最外层@autoreleasepool {} ：

runloop默认不开启，不会自动创建自动释放池，在需要使用自动释放池的时候，需要我们手动创建、添加自动释放池，此时如果所有的异步代码都写在自动释放池中，也可以理解为`当子线程销毁的时候，自动释放池释放`

#### 3. 自创建

线程中在一些代码场景中，自己创建的自动释放池，比如：

- 生成大量的临时变量
- 生成大容量对象
  - UIImage转NSData：UIImageJPEGRepresentation / UIImagePNGRepresentation 这两个方法在转为NSData的时候，这些Data都会写到内存中，如果图片太多，太大，就会导致内存暴涨。
  - [UIImage imageNamed: ]  会读入内存，所以相对的，速度也是最快的，Interface Builder（sb,xib）就是通过这个方法来加载的，图片被缓存，导致内存过大。

以上这些，都需要我们及时清理对象、内存，避免造成内存占用过高

```objc
for (int i = 0; i < 10000; ++i) {
    @autoreleasepool{
        NSString *str = @"Hello World";
        str = [str stringByAppendingFormat:@"- %d",i];
    } //此时，自动释放池的释放时机就是在此处：大括号完成的时候
}
```

注意：使用容器的block版本的枚举器时，内部会自动添加一个AutoreleasePool：

```objc
[array enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
    // 这里被一个局部@autoreleasepool包围着
}];
```
