//
//  PrintBlockRefObject.m
//  BlockExtendLayout
//
//  Created by coder on 2019/9/17.
//  Copyright © 2019 coder. All rights reserved.
//

#import "PrintBlockRefObject.h"

#import <objc/runtime.h>



//extend layout
enum {
    BLOCK_LAYOUT_ESCAPE = 0, // N=0 halt, rest is non-pointer. N!=0 reserved.
    BLOCK_LAYOUT_NON_OBJECT_BYTES = 1,    // N bytes non-objects
    BLOCK_LAYOUT_NON_OBJECT_WORDS = 2,    // N words non-objects
    BLOCK_LAYOUT_STRONG           = 3,    // N words strong pointers
    BLOCK_LAYOUT_BYREF            = 4,    // N words byref pointers
    BLOCK_LAYOUT_WEAK             = 5,    // N words weak pointers
    BLOCK_LAYOUT_UNRETAINED       = 6,    // N words unretained pointers
    BLOCK_LAYOUT_UNKNOWN_WORDS_7  = 7,    // N words, reserved
    BLOCK_LAYOUT_UNKNOWN_WORDS_8  = 8,    // N words, reserved
    BLOCK_LAYOUT_UNKNOWN_WORDS_9  = 9,    // N words, reserved
    BLOCK_LAYOUT_UNKNOWN_WORDS_A  = 0xA,  // N words, reserved
    BLOCK_LAYOUT_UNUSED_B         = 0xB,  // unspecified, reserved
    BLOCK_LAYOUT_UNUSED_C         = 0xC,  // unspecified, reserved
    BLOCK_LAYOUT_UNUSED_D         = 0xD,  // unspecified, reserved
    BLOCK_LAYOUT_UNUSED_E         = 0xE,  // unspecified, reserved
    BLOCK_LAYOUT_UNUSED_F         = 0xF,  // unspecified, reserved
};

// block flags
enum {
    BLOCK_DEALLOCATING =      (0x0001),  // runtime
    BLOCK_REFCOUNT_MASK =     (0xfffe),  // runtime
    BLOCK_NEEDS_FREE =        (1 << 24), // runtime
    BLOCK_HAS_COPY_DISPOSE =  (1 << 25), // compiler
    BLOCK_HAS_CTOR =          (1 << 26), // compiler: helpers have C++ code
    BLOCK_IS_GC =             (1 << 27), // runtime
    BLOCK_IS_GLOBAL =         (1 << 28), // compiler
    BLOCK_USE_STRET =         (1 << 29), // compiler: undefined if !BLOCK_HAS_SIGNATURE
    BLOCK_HAS_SIGNATURE  =    (1 << 30), // compiler
    BLOCK_HAS_EXTENDED_LAYOUT=(1 << 31)  // compiler
};


// Values for Block_byref->flags to describe __block variables
enum {
    // Byref refcount must use the same bits as Block_layout's refcount.
    // BLOCK_DEALLOCATING =      (0x0001),  // runtime
    // BLOCK_REFCOUNT_MASK =     (0xfffe),  // runtime
    
    BLOCK_BYREF_LAYOUT_MASK =       (0xf << 28), // compiler
    BLOCK_BYREF_LAYOUT_EXTENDED =   (  1 << 28), // compiler
    BLOCK_BYREF_LAYOUT_NON_OBJECT = (  2 << 28), // compiler
    BLOCK_BYREF_LAYOUT_STRONG =     (  3 << 28), // compiler
    BLOCK_BYREF_LAYOUT_WEAK =       (  4 << 28), // compiler
    BLOCK_BYREF_LAYOUT_UNRETAINED = (  5 << 28), // compiler
    
    BLOCK_BYREF_IS_GC =             (  1 << 27), // runtime
    
    BLOCK_BYREF_HAS_COPY_DISPOSE =  (  1 << 25), // compiler
    BLOCK_BYREF_NEEDS_FREE =        (  1 << 24), // runtime
};


typedef void(*BlockCopyFunction)(void *, const void *);
typedef void(*BlockDisposeFunction)(const void *);
typedef void(*BlockInvokeFunction)(void *, ...);
typedef void(*BlockByrefKeepFunction)(void *, void *);
typedef void(*BlockByrefDestroyFunction)(void *);
struct Block_descriptor_1 {
    uintptr_t reserved;
    uintptr_t size;
};


struct Block_descriptor_2 {
    // requires BLOCK_HAS_COPY_DISPOSE
    BlockCopyFunction copy;
    BlockDisposeFunction dispose;
};


struct Block_descriptor_3 {
    // requires BLOCK_HAS_SIGNATURE
    const char *signature;
    const char *layout;     // contents depend on BLOCK_HAS_EXTENDED_LAYOUT
};

struct Block_layout {
    void *isa;
    volatile int32_t flags; // contains ref count
    int32_t reserved;
    BlockInvokeFunction invoke;
    struct Block_descriptor_1 *descriptor;
    // imported variables
};

struct Block_byref {
    void *isa;
    struct Block_byref *forwarding;
    volatile int32_t flags; // contains ref count
    uint32_t size;
};

struct Block_byref_2 {
    // requires BLOCK_BYREF_HAS_COPY_DISPOSE
    BlockByrefKeepFunction byref_keep;
    BlockByrefDestroyFunction byref_destroy;
};

struct Block_byref_3 {
    // requires BLOCK_BYREF_LAYOUT_EXTENDED
    const char *layout;
};

@implementation PrintBlockRefObject

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class blockCls = NSClassFromString(@"NSBlock");
        class_replaceMethod(blockCls, @selector(description), (IMP)block_description, "@@:");
        
    });
}

static NSString *block_description(id block, SEL _cmd) {
    struct Block_layout *blockLayout = (__bridge struct Block_layout *)block;
    struct Block_descriptor_1 *desc1 = blockLayout->descriptor;
    struct Block_descriptor_2 *desc2 = NULL;
    struct Block_descriptor_3 *desc3 = NULL;
    
    NSMutableString *printStr = [NSMutableString new];
    
    if (blockLayout->flags & BLOCK_HAS_COPY_DISPOSE) {
        desc2 = (struct Block_descriptor_2 *)(desc1 + 1);
    } else {
        return printStr;
    }
    
    if (blockLayout->flags & BLOCK_HAS_EXTENDED_LAYOUT) {
        desc3 = (struct Block_descriptor_3 *)(desc2 + 1);
    } else {
        return printStr;
    }
    
    if (desc3->layout == 0) {
        return printStr;
    }
    
    
    const char *extendLayout = desc3->layout;
    
    //如果layout小于0x1000，则将layout本身当成一个12bit的数据，此时是compact encoding
    //压缩编码方式0xXYZ: X表示强引用数量，Y表示__block引用数量，Z表示弱引用数量，对该编码解码，从而统一下面的处理逻辑
    if (extendLayout < (const char *)0x1000) {
        char compactEncoding[4] = {0,0,0,0};
        unsigned short xyz = (unsigned short)extendLayout;
        unsigned char x = (xyz >> 8) & 0xf;
        unsigned char y = (xyz >> 4) & 0xf;
        unsigned char z = (xyz & 0xf);
        
        int idx = 0;
        if (x) {
            x--;
            compactEncoding[idx++] = (BLOCK_LAYOUT_STRONG << 4) | x;
        }
        if (y) {
            y--;
            compactEncoding[idx++] = (BLOCK_LAYOUT_BYREF << 4) | y;
        }
        if (z) {
            z--;
            compactEncoding[idx++] = (BLOCK_LAYOUT_WEAK << 4) | z;
        }
        extendLayout = compactEncoding;
    }
    
    //上面的代码解码了compact encoding情况
    //下面进行layout的解析,block内部会优先把对象类型排在前面
    
    
    //当layout大于0x1000,layout就是指向了一个字符串的指针
    int index = 0;
    int objOffest = sizeof(struct Block_layout);//block内部对象的偏移
    
    char *typeArr[4] = {"strong  ","byref   ","weak    ","unretain"};
    char *byrefTypeArr[3] = {"__strong __block","__weak __block","__unsafe_unretained __block"};
    
    
    while (extendLayout[index] != '\0') {
        
        unsigned char PN = extendLayout[index];
        unsigned char P = (PN >> 4) & 0xf; // 类型描述，strong，byref，weak等等
        unsigned char N = (PN & 0xf) + 1; //对应类型的个数
        
        //只针对对象类型进行判断
        if (P >= BLOCK_LAYOUT_STRONG && P <= BLOCK_LAYOUT_UNRETAINED) {
            
            int typeIndex = P - BLOCK_LAYOUT_STRONG;
            
            if (P != BLOCK_LAYOUT_BYREF) {
                [printStr appendFormat:@"\n引用类型：%s, 引用对象：",typeArr[typeIndex]];
                for (int i = 0; i < N; i++) {
                    
                    void *objPointer = *(void **)((void *)blockLayout + objOffest);
                    id obj = (__bridge id)(objPointer);
                    
                    [printStr appendFormat:@"%@",obj];
                    if (i != N - 1) {
                        [printStr appendString:@"，"];
                    }
                    
                    objOffest += sizeof(void *);//因为都是对象类型，每次偏移一个指针的大小
                }
                
            } else {
                //额外处理__block封装的类型，严格来说byref不能算是对象类型，虽然它有isa，但是该值被设为了0
                [printStr appendFormat:@"\n引用类型：%s, 引用对象：",typeArr[typeIndex]];
                
                NSInteger byrefObjCount = 0;//计数byref封装obj的数量
                
                
                for (int i = 0; i < N; i++) {
                    
                    struct Block_byref *byref1 = *(struct Block_byref **)((void *)blockLayout + objOffest);
                    byref1 = byref1->forwarding;
                    if ((byref1->flags & BLOCK_BYREF_LAYOUT_MASK) != BLOCK_BYREF_LAYOUT_NON_OBJECT) {//说明是obj对象
                        int byrefTypeIndex = (((byref1->flags - BLOCK_BYREF_LAYOUT_STRONG) >> 28) & 0xf);
                        
                        void *objPointer = *(void **)((void *)byref1 + byref1->size - sizeof(void *));
                        id obj = (__bridge id)(objPointer);
                        
                        if (byrefObjCount > 0) {
                            [printStr appendString:@"，"];
                        }
                        [printStr appendFormat:@"%@(%s)",obj, byrefTypeArr[byrefTypeIndex]];
                        
                        byrefObjCount++;
                    }
                    
                    objOffest += sizeof(void *);//因为都是对象类型，每次偏移一个指针的大小
                }
                
                if (byrefObjCount == 0) {
                    [printStr appendString:@"无__block修饰的对象"];
                }
                
            }
            
        }
        
        index++;
    }
    
    return printStr;
}

@end
