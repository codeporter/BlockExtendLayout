//
//  ViewController.m
//  BlockExtendLayout
//
//  Created by coder on 2019/9/17.
//  Copyright © 2019 coder. All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    id strongObj = [NSObject new];
    __block id blockRef = self;
    __block int blockInt = 10;
    __weak id weakObj = self;
    __weak __block id block_weak_obj = weakObj;
    __unsafe_unretained id unretainObj = self;
    short shortVal = 1;
    int intVal = 2;
    long longVal = 3;
    void(^block)(void) = [^(void) {
        
        [strongObj description];
        [blockRef description];
        blockInt = 11;
        [weakObj description];
        [unretainObj description];
        [block_weak_obj description];
        
        __unused long val = shortVal + intVal + longVal;
        
    } copy];
    
    NSLog(@"%@", [(id)block description]);
}


@end
