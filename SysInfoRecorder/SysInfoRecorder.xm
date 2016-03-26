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

    // remove old log file
    NSString *path = [NSString stringWithFormat:@"/tmp/%@.plist", [NSBundle mainBundle].bundleIdentifier];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
    
    // creat a container for recording the log
    logList = [[NSMutableArray alloc] init];
    
    // get current FPS
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

// get current CPU usage
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

// get current RAM usage
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

%hook NSObject
%new
- (void)displayLinkTick:(CADisplayLink *)displayLink
{
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

%new
- (void)onTimer
{
    // get launched time
    clock_t t1 = clock();
    double time = 1000.0 * t1 / CLOCKS_PER_SEC;
    
    NSMutableDictionary *logInfo = [[NSMutableDictionary alloc] init];
    [logInfo setObject:[NSString stringWithFormat:@"%.2f ms", time] forKey:@"已运行"];
    [logInfo setObject:[NSString stringWithFormat:@"%.2f%%", cpu_usage()] forKey:@"CPU 使用率"];
    [logInfo setObject:[NSString stringWithFormat:@"%.2f MB", usedMemory()] forKey:@"内存 已使用"];
    [logInfo setObject:[NSString stringWithFormat:@"%.2f", currentFPS] forKey:@"FPS"];
    
    [logList addObject:logInfo];
}

%new

- (void)writeLogsToFile
{
    NSString *path = [NSString stringWithFormat:@"/tmp/%@.plist", [NSBundle mainBundle].bundleIdentifier];
    
    [logList writeToFile:path atomically:YES];
}

%end

%hook UIApplication
- (void)setDelegate:(id)delegate
{
    %orig;
    Method method1 = class_getInstanceMethod([delegate class], @selector(application:didFinishLaunchingWithOptions:));
    class_addMethod([delegate class], @selector(myApplication:didFinishLaunchingWithOptions:), (IMP)myDidFinishLaunchingWithOptions_imp, method_getTypeEncoding(method1));
    Method method2 = class_getInstanceMethod([delegate class], @selector(myApplication:didFinishLaunchingWithOptions:));
    method_exchangeImplementations(method1, method2);
    
    Method method3 = class_getInstanceMethod([delegate class], @selector(applicationDidEnterBackground:));
    class_addMethod([delegate class], @selector(myApplicationDidEnterBackground:), (IMP)myApplicationDidEnterBackground_imp, method_getTypeEncoding(method3));
    Method method4 = class_getInstanceMethod([delegate class], @selector(myApplicationDidEnterBackground:));
    method_exchangeImplementations(method3, method4);
}

%end
