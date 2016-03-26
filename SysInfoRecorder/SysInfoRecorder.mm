#line 1 "/Projects/SysInfoRecorder/SysInfoRecorder/SysInfoRecorder/SysInfoRecorder.xm"
#import <UIKit/UIKit.h>
#include <sys/sysctl.h>
#include <mach/mach.h>
#import <objc/runtime.h>
#import <Foundation/NSObject.h>
#import <QuartzCore/CABase.h>
#import <QuartzCore/CADisplayLink.h>

double currentFPS;
NSMutableArray *logList;

@interface NSObject(my)

- (BOOL)myApplication:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions;
- (void)myApplicationDidEnterBackground:(UIApplication *)application;
- (void)displayLinkTick:(CADisplayLink *)displayLink;
- (void)onTimer;
- (void)writeLogsToFile;

float cpu_usage();
double usedMemory();

@end

id myDidFinishLaunchingWithOptions_imp(id self, SEL cmd, UIApplication *application, NSDictionary *launchOptions)
{
    BOOL ret = [self myApplication:application didFinishLaunchingWithOptions:launchOptions];

    
    NSString *path = [NSString stringWithFormat:@"/tmp/%@.plist", [NSBundle mainBundle].bundleIdentifier];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
    
    
    logList = [[NSMutableArray alloc] init];
    
    
    CADisplayLink *displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayLinkTick:)];
    [displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(onTimer) userInfo:nil repeats:YES];
    [timer fire];
    
    return @(ret);
}

id myApplicationDidEnterBackground_imp(id self, SEL cmd, UIApplication *application, NSDictionary *launchOptions)
{
    [self myApplicationDidEnterBackground:application];
    
    [self writeLogsToFile];
}


float cpu_usage()
{
    kern_return_t kr;
    task_info_data_t tinfo;
    mach_msg_type_number_t task_info_count;
    
    task_info_count = TASK_INFO_MAX;
    kr = task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)tinfo, &task_info_count);
    if (kr != KERN_SUCCESS) {
        return -1;
    }
    
    task_basic_info_t      basic_info;
    thread_array_t         thread_list;
    mach_msg_type_number_t thread_count;
    
    thread_info_data_t     thinfo;
    mach_msg_type_number_t thread_info_count;
    
    thread_basic_info_t basic_info_th;
    uint32_t stat_thread = 0;
    
    basic_info = (task_basic_info_t)tinfo;
    
    kr = task_threads(mach_task_self(), &thread_list, &thread_count);
    if (kr != KERN_SUCCESS) {
        return -1;
    }
    if (thread_count > 0)
        stat_thread += thread_count;
    
    long tot_sec = 0;
    long tot_usec = 0;
    float tot_cpu = 0;
    int j;
    
    for (j = 0; j < thread_count; j++)
    {
        thread_info_count = THREAD_INFO_MAX;
        kr = thread_info(thread_list[j], THREAD_BASIC_INFO,
                         (thread_info_t)thinfo, &thread_info_count);
        if (kr != KERN_SUCCESS) {
            return -1;
        }
        
        basic_info_th = (thread_basic_info_t)thinfo;
        
        if (!(basic_info_th->flags & TH_FLAGS_IDLE)) {
            tot_sec = tot_sec + basic_info_th->user_time.seconds + basic_info_th->system_time.seconds;
            tot_usec = tot_usec + basic_info_th->system_time.microseconds + basic_info_th->system_time.microseconds;
            tot_cpu = tot_cpu + basic_info_th->cpu_usage / (float)TH_USAGE_SCALE * 100.0;
        }
        
    }
    
    kr = vm_deallocate(mach_task_self(), (vm_offset_t)thread_list, thread_count * sizeof(thread_t));
    assert(kr == KERN_SUCCESS);
    
    return tot_cpu;
}


double usedMemory()
{
    task_basic_info_data_t taskInfo;
    mach_msg_type_number_t infoCount = TASK_BASIC_INFO_COUNT;
    kern_return_t kernReturn = task_info(mach_task_self(),
                                         TASK_BASIC_INFO, (task_info_t)&taskInfo, &infoCount);
    if(kernReturn != KERN_SUCCESS) {
        return NSNotFound;
    }
    
    return taskInfo.resident_size / 1024.0 / 1024.0;
}

#include <logos/logos.h>
#include <substrate.h>
@class NSObject; @class UIApplication; 
static void _logos_method$_ungrouped$NSObject$displayLinkTick$(NSObject*, SEL, CADisplayLink *); static void _logos_method$_ungrouped$NSObject$onTimer(NSObject*, SEL); static void _logos_method$_ungrouped$NSObject$writeLogsToFile(NSObject*, SEL); static void (*_logos_orig$_ungrouped$UIApplication$setDelegate$)(UIApplication*, SEL, id); static void _logos_method$_ungrouped$UIApplication$setDelegate$(UIApplication*, SEL, id); 

#line 131 "/Projects/SysInfoRecorder/SysInfoRecorder/SysInfoRecorder/SysInfoRecorder.xm"



static void _logos_method$_ungrouped$NSObject$displayLinkTick$(NSObject* self, SEL _cmd, CADisplayLink * displayLink) {
    static CFTimeInterval lastTimeInterval = 0.0;
    
    CFTimeInterval cuTime = CACurrentMediaTime();
    if (!lastTimeInterval) {
        lastTimeInterval = cuTime;
        return;
    }
    
    CFTimeInterval newInterval = cuTime - lastTimeInterval;
    lastTimeInterval = cuTime;
    if (newInterval > 1.0 || newInterval <= 0) {
        return;
    }
    
    currentFPS = round(1.0/ newInterval);
}



static void _logos_method$_ungrouped$NSObject$onTimer(NSObject* self, SEL _cmd) {
    
    clock_t t1 = clock();
    double time = 1000.0 * t1 / CLOCKS_PER_SEC;
    
    NSMutableDictionary *logInfo = [[NSMutableDictionary alloc] init];
    [logInfo setObject:[NSString stringWithFormat:@"%.2f ms", time] forKey:@"已运行"];
    [logInfo setObject:[NSString stringWithFormat:@"%.2f%%", cpu_usage()] forKey:@"CPU 使用率"];
    [logInfo setObject:[NSString stringWithFormat:@"%.2f MB", usedMemory()] forKey:@"内存 已使用"];
    [logInfo setObject:[NSString stringWithFormat:@"%.2f", currentFPS] forKey:@"FPS"];
    
    [logList addObject:logInfo];
}




static void _logos_method$_ungrouped$NSObject$writeLogsToFile(NSObject* self, SEL _cmd) {
    NSString *path = [NSString stringWithFormat:@"/tmp/%@.plist", [NSBundle mainBundle].bundleIdentifier];
    
    [logList writeToFile:path atomically:YES];
}





static void _logos_method$_ungrouped$UIApplication$setDelegate$(UIApplication* self, SEL _cmd, id delegate) {
    _logos_orig$_ungrouped$UIApplication$setDelegate$(self, _cmd, delegate);
    Method method1 = class_getInstanceMethod([delegate class], @selector(application:didFinishLaunchingWithOptions:));
    class_addMethod([delegate class], @selector(myApplication:didFinishLaunchingWithOptions:), (IMP)myDidFinishLaunchingWithOptions_imp, method_getTypeEncoding(method1));
    Method method2 = class_getInstanceMethod([delegate class], @selector(myApplication:didFinishLaunchingWithOptions:));
    method_exchangeImplementations(method1, method2);
    
    Method method3 = class_getInstanceMethod([delegate class], @selector(applicationDidEnterBackground:));
    class_addMethod([delegate class], @selector(myApplicationDidEnterBackground:), (IMP)myApplicationDidEnterBackground_imp, method_getTypeEncoding(method3));
    Method method4 = class_getInstanceMethod([delegate class], @selector(myApplicationDidEnterBackground:));
    method_exchangeImplementations(method3, method4);
}


static __attribute__((constructor)) void _logosLocalInit() {
{Class _logos_class$_ungrouped$NSObject = objc_getClass("NSObject"); { char _typeEncoding[1024]; unsigned int i = 0; _typeEncoding[i] = 'v'; i += 1; _typeEncoding[i] = '@'; i += 1; _typeEncoding[i] = ':'; i += 1; memcpy(_typeEncoding + i, @encode(CADisplayLink *), strlen(@encode(CADisplayLink *))); i += strlen(@encode(CADisplayLink *)); _typeEncoding[i] = '\0'; class_addMethod(_logos_class$_ungrouped$NSObject, @selector(displayLinkTick:), (IMP)&_logos_method$_ungrouped$NSObject$displayLinkTick$, _typeEncoding); }{ char _typeEncoding[1024]; unsigned int i = 0; _typeEncoding[i] = 'v'; i += 1; _typeEncoding[i] = '@'; i += 1; _typeEncoding[i] = ':'; i += 1; _typeEncoding[i] = '\0'; class_addMethod(_logos_class$_ungrouped$NSObject, @selector(onTimer), (IMP)&_logos_method$_ungrouped$NSObject$onTimer, _typeEncoding); }{ char _typeEncoding[1024]; unsigned int i = 0; _typeEncoding[i] = 'v'; i += 1; _typeEncoding[i] = '@'; i += 1; _typeEncoding[i] = ':'; i += 1; _typeEncoding[i] = '\0'; class_addMethod(_logos_class$_ungrouped$NSObject, @selector(writeLogsToFile), (IMP)&_logos_method$_ungrouped$NSObject$writeLogsToFile, _typeEncoding); }Class _logos_class$_ungrouped$UIApplication = objc_getClass("UIApplication"); MSHookMessageEx(_logos_class$_ungrouped$UIApplication, @selector(setDelegate:), (IMP)&_logos_method$_ungrouped$UIApplication$setDelegate$, (IMP*)&_logos_orig$_ungrouped$UIApplication$setDelegate$);} }
#line 195 "/Projects/SysInfoRecorder/SysInfoRecorder/SysInfoRecorder/SysInfoRecorder.xm"
