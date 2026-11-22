//
//  DTPUnlock.m
//  Target : com.dulatrackpro.aix  (DulaTrackPro AI X 2.8 / build 10.30)
//  Purpose: 强制 DTPStoreKitHelper 的订阅权益检查返回"已订阅"
//
//  依据: 从 __LINKEDIT 明文符号表中恢复出的真实接口
//    DTPStoreKitHelper
//      - checkEntitlement(completion: (Bool, Bool, Date?, Date?) -> Void)
//      - syncAndCheckEntitlement(completion: (Bool, Bool, Date?, Date?, String?, String?) -> Void)
//      - purchase(productId:completion: (Bool, String?) -> Void)
//      - restore(completion: (Bool, String?) -> Void)
//
//  用法: 编译成 arm64 dylib，注入到解密后的 App，重签安装。
//        启动后看 Console 里的 [DTPUnlock] 日志即可确认是否命中。
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <string.h>
#import <stdlib.h>

// completion 回调类型（与上面恢复出的函数签名一一对应）
typedef void (^DTPEntitlementCB)(BOOL active, BOOL autoRenew, NSDate *endA, NSDate *endB);
typedef void (^DTPSyncCB)(BOOL active, BOOL autoRenew, NSDate *endA, NSDate *endB, NSString *s1, NSString *s2);
typedef void (^DTPPurchaseCB)(BOOL ok, NSString *message);

static NSDate *dtp_farFuture(void) {
    return [NSDate dateWithTimeIntervalSinceNow:3600.0 * 24 * 365 * 10];
}

#pragma mark - 替换实现

static void dtp_checkEntitlement(id self, SEL _cmd, id completion) {
    NSLog(@"[DTPUnlock] -> %@", NSStringFromSelector(_cmd));
    if (completion) {
        DTPEntitlementCB cb = (DTPEntitlementCB)completion;
        NSDate *far = dtp_farFuture();
        cb(YES, YES, far, far);
    }
}

static void dtp_syncAndCheckEntitlement(id self, SEL _cmd, id completion) {
    NSLog(@"[DTPUnlock] -> %@", NSStringFromSelector(_cmd));
    if (completion) {
        DTPSyncCB cb = (DTPSyncCB)completion;
        NSDate *far = dtp_farFuture();
        cb(YES, YES, far, far, @"unlocked", @"unlocked");
    }
}

// 兜底：把 purchase / restore 结果也强制成成功
static void dtp_purchase(id self, SEL _cmd, id a1, id completion) {
    NSLog(@"[DTPUnlock] -> %@", NSStringFromSelector(_cmd));
    if (completion) {
        DTPPurchaseCB cb = (DTPPurchaseCB)completion;
        cb(YES, @"unlocked");
    }
}

static void dtp_restore(id self, SEL _cmd, id completion) {
    NSLog(@"[DTPUnlock] -> %@", NSStringFromSelector(_cmd));
    if (completion) {
        DTPPurchaseCB cb = (DTPPurchaseCB)completion;
        cb(YES, @"unlocked");
    }
}

#pragma mark - 查找 & 安装

static Class dtp_findClassBySuffix(const char *needle) {
    int count = objc_getClassList(NULL, 0);
    if (count <= 0) return Nil;
    Class *classes = (Class *)malloc(sizeof(Class) * count);
    if (!classes) return Nil;
    count = objc_getClassList(classes, count);
    Class found = Nil;
    for (int i = 0; i < count; i++) {
        const char *name = class_getName(classes[i]);
        if (name && strstr(name, needle)) { found = classes[i]; break; }
    }
    free(classes);
    return found;
}

static int dtp_argCount(SEL sel) {
    const char *s = sel_getName(sel);
    int n = 0;
    for (const char *p = s; *p; p++) if (*p == ':') n++;
    return n;
}

static void dtp_installHooks(void) {
    Class cls = dtp_findClassBySuffix("DTPStoreKitHelper");
    if (!cls) {
        // Swift 类可能延迟注册，稍后重试
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ dtp_installHooks(); });
        return;
    }

    unsigned int mcount = 0;
    Method *methods = class_copyMethodList(cls, &mcount);
    NSLog(@"[DTPUnlock] class=%s methods=%u", class_getName(cls), mcount);

    int hooked = 0;
    for (unsigned int i = 0; i < mcount; i++) {
        SEL sel = method_getName(methods[i]);
        const char *name = sel_getName(sel);
        const char *types = method_getTypeEncoding(methods[i]);
        NSLog(@"[DTPUnlock]   - %s  types=%s", name, types);

        IMP imp = NULL;
        if (strstr(name, "syncAndCheckEntitlement")) {
            imp = (IMP)dtp_syncAndCheckEntitlement;
        } else if (strstr(name, "checkEntitlement")) {
            imp = (IMP)dtp_checkEntitlement;
        } else if (strstr(name, "purchase") && dtp_argCount(sel) == 2) {
            imp = (IMP)dtp_purchase;
        } else if (strstr(name, "restore") && dtp_argCount(sel) == 1) {
            imp = (IMP)dtp_restore;
        }
        if (imp) {
            method_setImplementation(methods[i], imp);
            hooked++;
        }
    }
    free(methods);
    NSLog(@"[DTPUnlock] hooked %d method(s)", hooked);
    if (hooked == 0) {
        NSLog(@"[DTPUnlock] WARN: 没有命中任何方法 —— 这些 Swift 方法可能是静态派发，"
              @"需要改用解密二进制直接 patch 函数体");
    }
}

__attribute__((constructor))
static void dtp_unlock_init(void) {
    NSLog(@"[DTPUnlock] dylib loaded (pid=%d)", getpid());
    dtp_installHooks();
}
