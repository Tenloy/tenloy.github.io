---
title: Objective-C — Block
date: 2020-09-06 09:37:02
urlname: oc-block.html
tags:
categories:
  - iOS
---

## 一、什么是Blocks

> Blocks是C语言的扩充功能，可以用一句话表示这个功能：带有自动变量(局部变量)的匿名函数

编译后：就是在**文件中的一个函数**。

在C中可能使用的变量

- 自动变量(局部变量)
- 函数的参数
- 静态变量(静态局部变量)
- 静态全局变量
- 全局变量

其中，在后三种，在文件中的任何地方都能访问到。

**研究Blocks的重点就是：在Blocks中，怎么访问、存储、改变前两种数据。**

“带有自动变量值的匿名函数”这一概念并不仅指Blocks，还存在与其他编程语言，也被称为：

- Block：`C + Blocks`、`Smalltalk`、`Ruby`
- 闭包(Closure)：`swift`
- lambda计算（λ计算，lambda calculus等）：`LISP`、`Python`、`C++ 11`
- Anonymous function(匿名函数)：`JavaScript`

## 二、Block类型变量

完整形式的Block类型变量定义语法 与 C语言函数定义，仅有两点不同：

- 没有函数名：因为是匿名函数
- 带有 ^ ：返回值类型钱带有'^'(插入记号，caret)记号，因为OS X、iOS中大量使用Block，便于查找
  - 不完整形式的Block类型变量：可以省略返回值类型、参数列表

### 2.1 C 函数指针

```go
int func (int count) {
    return count + 1;
}
int (*funcptr) (int) = &func;
```

### 2.2 OC Block

在Block语法下，可将Block语法赋值给 Block类型的变量。

在Block中的文档中，“Block”既指源代码中的**Block语法**，也指由Block语法**生成的值**。

```go
int (^blk) (int);  
```

比较：

1. 相比C而言，仅仅是将* 改成了 ^
2. 调用起来没有区别

## 三、Block的实质

### 3.1 代码反编译看Block

clang(LLVM 编译器)具有转换为我们可读源代码的功能，我们可以通过`-rewrite-objc`将含有Block语法的源代码变换为C++的源代码，本质上是C语言源代码：

```bash
clang -rewrite-objc 源代码文件名
```

代码转换：

```cpp
int main(){
    void(^blk)(void)=^{ printf("Block\n");};
    blk();
    return 0;
}
```

源代码通过clang可变换为以下形式：

```c++
//从其名称可以联想到某些标志、今后版本升级所需的区域以及函数指针。
struct __block_impl {
    void *isa;
    int Flags;
    int Reserved;
    vold *Funcptr;  
}

// Block类型变量对应的结构体
struct __main_block_impl_0 {
    struct __block_impl imp1;   
    struct __main_block_desc_0* Desc;
    //默认构造函数，C++中的语法
    __main_block_impl_0(void *fp, struct __main_block_desc_0 *desc, int flags=0) {
        imp1.isa = &_NSConcreteStackBlock;
        imp1.Flags = flags  //不传默认=0，Reserved默认也是0
        imp1.FuncPtr = fp;
        Desc = desc:
    }
};

//该函数的参数__cself相当于C++实例方法中指向实例自身的变量this，或是Objective-C实例方法中指向对象自身的变量self
//即参数__cself为`指向Block值的变量`
static void __main_block_func_0(struct __main_block_impl_0* cself)
{
    printf("Block\n");
}

//今后版本升级所需的区域和Block的大小
static struct __main_block_desc_0{
    unsigned long reserved;
    unsigned long Block_size;
} __main_block_desc_0_DATA = {
    0,
    sizeof(struct __main_block_impl_0)   //block对应结构体的实例大小
};

int main()
{
    //创建 构造函数
      /*
        相当于(《OC 高级编程》中写的)：
        struct __main_block_impl_0 tmp = __main_block_impl_0(__main_block_func_0, &__main_block_desc_0_DATA);
        struct __main_block_impl_0 * blk = &tmp;
        相当于源码：void(^blk)(void) = ^{printf("Block\n");};
       
        @param  __main_block_func_0  函数
        @param  &__main_block_desc_0_DATA 结构体指针  "静态全局变量"
      */
    void (*blk)(void) = (void(*)(void)) &__main_block_impl_0((void *)__main_block_func_0, &__main_block_desc_0_DATA);  

    //调用
      /*
        问题：blk明明是__main_block_impl_0结构体类型指针的，为什么变成__block_impl结构体类型指针了？
        答：因为__block_impl作为__main_block_impl_0的首成员，所以两个结构体的首地址都是相同的，所以完全可以强转，只不过使用__block_impl就访问不了__main_block_impl_0结构体中其他的几个成员变量，只能访问__block_impl自己的。
      */
    （ (void (*)(struct __block_impl *)) ((struct __block_impl *)blk)->FuncPtr )((struct __block_impl *)blk);

    return 0;
}
```

### 3.2 &_NSConcreteStackBlock 是什么

在讲 `&_NSConcreteStackBlock` 与 `isa` 之前，先了解一下 `class`、`id` 这两个关键字的定义：

```cpp
struct objc_class {
    Class isa;
}
typedef struct objc_class * class;

struct objc_object{
    Class isa;
}
typedef struct objc_object * id;
```

isa：是一个Class 类型的指针. 
- 每个实例对象有个isa的指针，他指向对象的类Class
- Class里也有个isa的指针， 指向meteClass(元类)。
- 元类（meteClass）也是类，它也是对象。元类也有isa指针，它的isa指针最终指向的是一个根元类(root meteClass). 
- 根元类的isa指针指向本身，这样形成了一个封闭的内循环。

元类保存了类方法的列表。当类方法被调用时，先会从本身查找类方法的实现，如果没有，元类会向他父类查找该方法。

### 3.3 小结

- 每个对象、类本质上都是结构体，都有isa指针。
- 每个结构体都持有对象、类的属性、方法的名称、方法的实现(函数指针)、以及父类的指针。
- `&_NSConcreteStackBlock`相当于Block isa指向的类，在将Block作为OC对象处理时，关于该类的信息放置于`_NSConcreteStackBlock`中。

总结：**Block即为Objective-C的对象，C中的结构体，底层实现是C语言中的函数**。

## 四、Block的存储域

Block存在三种不同作用域的对象：

- _NSConcreteStackBlock设置在栈上
- _NSConcreteGlobalBlock设置在程序的数据区域(.data区)
- _NSConcreteMallocBlock设置在由malloc函数分配的内存块(即堆)中

### 4.1 _NSConcreteGlobalBlock

- 像声明全局变量一样声明Block变量时
- 捕获全局变量、静态自动变量、静态全局变量时（**此时，如果同时满足 `_NSConcreteMallocBlock`的条件，那 `_NSConcreteMallocBlock` 优先**）
- 当不捕获任何自动变量时

### 4.2 _NSConcreteMallocBlock

- 调用Block的copy实例方法时；
- Block作为函数返回值返回时；
- 将Block赋值给附有__strong修饰符id类型的类或Block类型变量时；
- 在方法名含有usingBlock的Cocoa框架方法或Grand Central Dispatch的API传递Block时。

调用 `objc_retainBlock()` 方法，实际上也就是 `Block_copy` 函数

- 对栈上的Block执行copy方法，会从栈复制到堆；
- 对堆上的Block执行copy方法，引用计数增加；
- 对全局的Block执行copy方法，什么也不会发生。

所以，不管Block配置在何处，用copy方法都不会引起任何问题，不确定存储域的时候可以直接copy。

### 4.3 _NSConcreteStackBlock

除了以上讲述的情况，其他创建的Block存储于都是在栈上

ARC 无效时，一般需要我们手动将Block从栈复制到堆，然后手动释放。

- -retain
- -copy/Block_copy(block)
- -release/Block_release(block)

**对于栈上的block调用retain是无效的，只有先copy到堆上，再copy才会有效果。**

## 五、Block捕获自动变量机制

> 《Effective Objective-C 2.0》中说道：
>
> Block 默认会把所有捕获的局部变量copy一份到该块所在的内存空间。捕获了多少个变量，就要占据多少内存空间。（注意：拷贝对象时，**拷贝的并不是对象本身，而是指向这些对象的指针变量。**）
>
> block作用域完成，销毁的时候，会把捕获的对象 `release` 一次。

### 5.1 捕获自动变量值

> 正确理解Block的定义：带有自动变量**值**的匿名函数.

关于"本质是匿名函数"，上面已经讲过。正确理解"带有自动变量值"，也还是需要从**Block的底层实现是函数**出发。

#### 5.1.1 捕获规则

Block会自动截获定义语法中所使用到的**自动变量**(**全局变量、静态自动变量、静态全局变量不用截获，因为作用域的原因，可直接使用**)的值，即保存该自动变量的**瞬间值**。

- 定义后(保存后)修改，对调用时没有任何影响。
- 定义中修改自动变量值编译器报错。

**捕获非对象自动变量：**

- 可以使用，但是不能赋值变量

**捕获对象自动变量：**

- 可以使用对象的任何方法(比如：mutableArray的addObject都可以)，但是不能赋值变量
- 可以使用、赋值修改对象的属性

注意：

Blocks中，截获自动变量的方法并没有实现对C语言数组的截获。

```cpp
const char text[] = "hello";
// 在Block中使用text，获取元素是会编译报错的
// 可以使用指针
const char * text = "hello";
```

#### 5.1.2 实现原理

**实现原理跟C函数的值传递、地址传递结合理解。**

> 捕获自动变量的值的原因是：Block需要保证定义中使用的自动变量在外部随时可能释放，所以Block需要保留该变量(全局、静态因为不会被释放，所以Block对此类变量没有操作)。

##### 1. 没有捕获自动变量时

Block在没有拦截自动变量时的默认形式如下：

```objectivec
// Block类型变量对应的结构体
struct __main_block_impl_0 {
    struct __block_impl imp1;   
    struct __main_block_desc_0* Desc;
    //默认构造函数，C++中的语法
    __main_block_impl_0(void *fp, struct __main_block_desc_0 *desc, int flags=0) {
        imp1.isa = &_NSConcreteStackBlock;
        imp1.Flags = flags  //不传默认=0，Reserved默认也是0
        imp1.FuncPtr = fp;
        Desc = desc:
    }
};

//该函数的参数__cself相当于C++实例方法中指向实例自身的变量this，或是Objective-C实例方法中指向对象自身的变量self
//即参数__cself为`指向Block值的变量`
static void __main_block_func_0(struct __main_block_impl_0* cself)
{
    printf("Block\n");
}

//今后版本升级所需的区域和Block的大小
static struct __main_block_desc_0{
    unsigned long reserved;
    unsigned long Block_size;
} __main_block_desc_0_DATA = {
    0,
    sizeof(struct __main_block_impl_0)   //block对应结构体的实例大小
};

//定义
void (*blk)(void) = (void(*)(void)) &__main_block_impl_0((void *)__main_block_func_0, &__main_block_desc_0_DATA);  

//调用
((void (*)(struct __block_impl *)) ((struct __block_impl *)blk)->FuncPtr)((struct __block_impl *)blk);
```

Block将语法表达式中使用到的自动变量作为成员变量追加到了Block类型变量对应的结构体 `__main_block_impl_0` 中。

##### 2. 捕获非OC对象自动变量

反编译代码：

```rust
// Block类型变量对应的结构体
struct __main_block_impl_0 {
    struct __block_impl imp1;   
    struct __main_block_desc_0* Desc;
    const char * fmt;
    int val;
    //默认构造函数，C++中的语法
    __main_block_impl_0(void *fp, struct __main_block_desc_0 *desc, const char * _fmt, int _val, int flags=0) : fmt(_fmt), val(_val) {
        imp1.isa = &_NSConcreteStackBlock;
        imp1.Flags = flags  //不传默认=0，Reserved默认也是0
        imp1.FuncPtr = fp;
        Desc = desc:
    }
};

//该函数的参数__cself相当于C++实例方法中指向实例自身的变量this，或是Objective-C实例方法中指向对象自身的变量self
//即参数__cself为`指向Block值的变量`
static void __main_block_func_0(struct __main_block_impl_0* cself) {
      const char * fmt = __cself->fmt;
      int val = __cself->val;
      printf(fmt, val);
}

//今后版本升级所需的区域和Block的大小
static struct __main_block_desc_0{
    unsigned long reserved;
    unsigned long Block_size;
} __main_block_desc_0_DATA = {
    0,
    sizeof(struct __main_block_impl_0)   //block对应结构体的实例大小
};

    //定义
     void (*blk)(void) = (void(*)(void)) &__main_block_impl_0((void *)__main_block_func_0, &__main_block_desc_0_DATA, fmt, val);  
    //调用
    （ (void (*)(struct __block_impl *)) ((struct __block_impl *)blk)->FuncPtr )((struct __block_impl *)blk);
```

##### 3. 捕获OC对象自动变量

现状：

- Block将语法表达式中使用到的自动变量作为成员变量追加到了Block类型变量对应的结构体 `__main_block_impl_0` 中。
- C语言结构体不能含有附有__strong修饰符的变量，因为编译器不知道何时进行C语言结构体的初始化和废弃操作，不能很好的管理内存。

拦截NSArray对象自动变量反编译代码：

```rust
// =========OC代码=========
id array = [[NSMutableArray alloc] init];
blk = [^(id obj) {
    [array addObject: obj];
    NSLog(@“array count = %ld”, [array count]);
} copy];

blk([NSObject new]);

// ========反编译代码========
// Block类型变量对应的结构体
struct __main_block_impl_0 {
    struct __block_impl imp1;   
    struct __main_block_desc_0* Desc;
    id __strong array;
    //默认构造函数，C++中的语法
    __main_block_impl_0(void *fp, struct __main_block_desc_0 *desc, id __strong _array, int flags=0): array(_array) {
        imp1.isa = &_NSConcreteStackBlock;
        imp1.Flags = flags  //不传默认=0，Reserved默认也是0
        imp1.FuncPtr = fp;
        Desc = desc:
    }
};

//该函数的参数__cself相当于C++实例方法中指向实例自身的变量this，或是Objective-C实例方法中指向对象自身的变量self
//即参数__cself为`指向Block值的变量`
static void __main_block_func_0(struct __main_block_impl_0* cself, id obj) {
    id __strong array = __cself->array;
    [array addObject:obj];
    NSLog(@“array count = %ld”, [array count]);
}

/*
使用_Block_object_assign函数将 对象类型 对象赋值给Block结构体的成员变量array，并持有该对象
_Block_object_assign函数调用相当于retain实例方法的函数
*/
static void __main_block_copy_0(struct __main_block_impl_0 *dst, struct __main_block_impl_0 * src) {
  _Block_object_assign(&dst->array, src->array, BLOCK_FIELD_IS_OBJECT);
}

/*
 Block_object_dispose函数调用相当于release实例方法的函数，释放Block结构体成员变量array中的对象
*/
static void __main_block_dispost_0(struct __main_block_impl_0 * src) {
  _Block_object_dispose(src->array, BLOCK_FIELD_IS_OBJECT);
}

//今后版本升级所需的区域和Block的大小
static struct __main_block_desc_0{
    unsigned long reserved;
    unsigned long Block_size;
    void (*copy)(struct __main_block_impl_0*, struct __main_block_impl_0 *);
    void(*dispose)(struct __main_block_impl_0 *);
} __main_block_desc_0_DATA = {
    0,
    sizeof(struct __main_block_impl_0),   //block对应结构体的实例大小
    __main_block_copy_0,
    __main_block_dispose_0
};

    //定义
     void (*blk)(void) = (void(*)(void)) &__main_block_impl_0((void *)__main_block_func_0, &__main_block_desc_0_DATA, fmt, val);  
    //调用
    （ (void (*)(struct __block_impl *)) ((struct __block_impl *)blk)->FuncPtr )((struct __block_impl *)blk);
```

**内部实现:**
在 `__main_block_desc_0` 结构体中增加的成员变量 copy 和 dispose , 以及作为指针赋值给该成员变量 `__main_block_copy_0` 函数和 `__main_block_dispose_0` 函数。

- 用途：在上面代码段中有注明
- 调用时机：在上面转换的源码中，没有发现调用。在Block从栈赋值到堆上(`即_Block_copy函数`)以及堆上的Block被废弃时`才会`调用这些函数
- 在 `__block` 变量时，也是这两个方法，不过其中有些不同，**对象是`BLOCK_FIELD_IS_OBJECT`，`__block` 变量是 `BLOCK_FIELD_IS_BYREF` ，通过这两个参数区分两种类型**。不过持有、释放时机与机制都是一样的。

这是为什么堆上的Block捕获的对象与 `__block` 类型变量能超出变量作用域而存在。

### 5.2 __block存储域说明符

使用附有 `__block` 说明符的自动变量可在Block中修改、赋值，此类变量称为 `__block变量`。

**`__block`修饰的变量，在block定义后，还可以修改，之后的block调用时，是变量的最新赋值。**(因为此时Block捕获的都是地址。)

#### 5.2.1 存储域类说明符

C语言有以下存储域类说明符：

- typedef
- extern
- static 表示作为静态变量存储在数据区中
- auto 表示作为自动变量存储在栈中
- register

`__block` 说明符类似于static、auto和register，用于指定将变量值设置到哪个存储域中。

#### 5.2.2 实现原理

block拦截 `__block` 变量与拦截全局、静态全局变量的代码分析：

- 拦截全局、静态全局变量：
  - 没有形态改变，在源码中也是以全局变量、静态全局变量形态存在；
  - 原处定义相同的代码，`__main_block_func_0` 中直接使用变量；
  - *其他与默认的Block的源码一样*。
- 拦截静态自动变量(与上面看到的拦截自动变量形式一样)。比如：
  - 在原处定义static int static_auto_val = 3;
  - 在 `__main_block_impl_0` 中增加了成员变量 `int * static_auto_val;` 指向该静态变量的指针
  - *其他与默认的Block的源码一样*。
- 拦截`__block` 变量。比如：
  ```objc
  __block int val = 10;
  __block id __strong(/*默认*/) obj = [[NSObject alloc] init];
  ```

反编译代码：

```rust
//__block变量如同Block一样变为了结构体__Block_byref_val_0实例、__Block_byref_obj_0实例
struct __Block_byref_val_0 {
  void * _isa;
  __Block_byref_val_0 * __forwarding;  //指向自身，确保__block是配置在堆上还是在栈上，都可以通过这个指针正确访问栈上的__block变量和堆上的__block变量
  int __flags;
  int __size;
  int val;  //原先变量值，意味着该结构体持有相当于原自动变量的成员变量
}

static void __main_block_copy_0 (struct __main_block_impl_0*dst, struct __main_block_impl_0*src){
  __Block_object_assign(&dst->val, src-val, Block_FIELD_IS_BYREF);
}

static void __main_block_dispost_0(struct __main_block_impl_0 * src)
{
  _Block_object_dispose(src->array, Block_FIELD_IS_BYREF);
}

struct __Block_byref_obj_0 {
  void * __isa;
  __Block_byref_obj_0 * __forwarding;
  int __flags;
  int __size;
  void (*__Block_byref_id_object_copy)(void*, void*);
  void (*__Block_byref_id_object_dispose)(void*);
  __strong id obj;
}

static void __Block_byref_id_object_copy_131 (void *dst, void*src){
  __Block_object_assign((char *)dst + 40, *(void * *)  ((char *)src+40), 131);
}
static void __Block_byref_id_object_dispose_131(void* src)
{
  _Block_object_dispose(*(void * *)   ((char *)src+40), 131);
}

// __main_block_impl_0结构体新增成员变量__Block_byref_val_0 *val;
static void_main_block_func_0(struct __main_block_impl_0 * __cself){
  __Block_byref_val_0 * val = __cself->val;
  (val->__forwarding->val);  //具体使用
}

//今后版本升级所需的区域和Block的大小
static struct __main_block_desc_0{
    unsigned long reserved;
    unsigned long Block_size;
    void (*copy)(struct __main_block_impl_0*, struct __main_block_impl_0 *);
    void(*dispose)(struct __main_block_impl_0 *);
} __main_block_desc_0_DATA = {
    0,
    sizeof(struct __main_block_impl_0),   //block对应结构体的实例大小
    __main_block_copy_0,
    __main_block_dispose_0
};


//定义
__Block_byref_val_0 val = {
    0,
    &val,
    0,
    sizeof(__Block_byref_val_0),
    10  //原先变量值
}
__Block_byref_obj_0 obj = {
    0，
    &obj,
    0x2000000,
    sizeof(__Block_byref_obj_0),
    __Block_byref_id_object_copy_131,
    __Block_byref_id_object_dispose_131,
    [[NSObject alloc] init];
}
void (*blk)(void) = (void(*)(void)) &__main_block_impl_0((void *)__main_block_func_0, &__main_block_desc_0_DATA, &val, 0x22000000);  
//调用
((void (*)(struct __block_impl *)) ((struct __block_impl *)blk)->FuncPtr )((struct __block_impl *)blk);
```

由此可见，block对 `__block` 修饰的OC对象，与未用 `__block` 修饰的，在内存管理上几乎是一致的，`_Block_object_assign` 持有，`_Block_object_disposes` 释放。 `__block` 修饰的OC对象，只要 `__block` 变量还在堆上存在，就不会释放。只不过，`__block` 修饰的OC对象，不增加引用计数，block不retain变量。

以上对`__block`作用域修饰符的底部实现，做了反编译查看，那么 `__block` 变量具体是怎么运作的呢？

- 在block复制到堆上的时候， `__block` 变量也会复制到堆上，在block已经被复制到堆上的时候，再复制，对 `__block` 变量没有任何影响。当block被废弃的时候， `__block` 变量也会被释放。
- 当多个block引用 `__block` 变量时，引用计数增加。与OC的引用计数内存管理完全相同。从编译的源码来看，与block拦截OC自动变量时除了类型 `Block_FIELD_IS_BYREF` 不一样，其他都一样。
- `__forwarding`成员变量指向自身，确保 `__block` 是配置在堆上还是在栈上，都可以通过这个指针正确访问栈上或堆上的 `__block` 变量。
- 栈上的 `__block` 变量，在 `__block` 变量从栈上复制到堆上的时候，会将成员变量 `__forwarding` 的值替换为复制到的目标堆上的 `__block` 变量的地址。 这也能解释为什么 `__block` 修饰过的指针变量(对象名)，在block定义后，再打印对象名的地址，发现变为了堆上的地址。
- 栈上的 `__block` 变量，在block不发生复制，一直在栈上的时候，也不会发生复制，会仍然在栈上，不过此时__forwarding指向自身，会将自身传入block，不跟默认一样，复制指针变量传入。

最后两条也是为什么： `__block` 修饰的变量可以修改的原因。**可以保证 `__block` 变量在block中的修改，对外部真实有效。**

#### 5.2.3 __block与其他所有权修饰符结合

上面，讲的都是 `__block` 与默认的 `__strong` 修饰的现象。

- `__weak`与block的结合使用
  - block不管赋值、copy怎么操作，对外部__weak修饰的对象，不持有，这是避免循环引用的机制之一。
- `__block` 与 `__weak` 同时使用
  - 现象与 `__weak` 单独使用是一致的
- `__block` 与 `__autoreleasing` 不能同时使用。

#### 5.2.4 __block解决循环引用

根本机制是：

- MRC下，对__block修饰的变量，block不进行retain，引用计数不会增加。
- ARC下，`__block` 修饰时，可以在block中修改，置为nil，手动解除循环引用，但是比 `__weak` 的缺点是必须要执行block，要不然不触发置nil行为，还是会循环引用。