#import <substrate.h>
#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#include <math.h>

// ===================================================================
// CONFIG - Chỉnh sửa các thông số này để tùy chỉnh aimbot
// ===================================================================
#define AIMBOT_KEY          1       // 0=luôn bật, 1=khi bắn
#define AIM_RANGE           200.0f  // khoảng cách tối đa (mét)
#define AIM_SMOOTH          0.12f   // 0.0 = instant lock, 1.0 = chậm
#define AIM_BONE            1       // 0=head, 1=neck, 2=chest, 3=pelvis
#define AIM_FOV             25.0f   // góc nhìn (độ)
#define AIM_THROUGH_WALL    0       // 0=tắt, 1=bắn xuyên tường
#define ESP_ENABLED         1       // 0=tắt ESP, 1=bật ESP
#define AIMBOT_ENABLED      1       // 0=tắt, 1=bật
// ===================================================================

// Kiểu dữ liệu Unity
typedef struct { float x, y, z; } UnityVector3;
typedef struct { float x, y, z, w; } UnityQuaternion;

// Địa chỉ RVA từ dump.cs - Unity Engine APIs (không obfuscated)
// ---------------------------------------------------------------
// UnityEngine.Camera
#define RVA_CAMERA_GET_MAIN               0x8599008
#define RVA_CAMERA_GET_CURRENT            0x8599048
#define RVA_CAMERA_WORLD_TO_SCREEN_POINT  0x8598914  // WorldToScreenPoint(Vector3)
#define RVA_CAMERA_WORLD_TO_SCREEN_POINT_EYE 0x8598514 // + eye enum
#define RVA_CAMERA_SCREEN_TO_WORLD_POINT  0x8598A70

// UnityEngine.GameObject
#define RVA_GAMEOBJECT_FIND_WITH_TAG          0x85F6D1C
#define RVA_GAMEOBJECT_FIND_GAMEOBJECT_WITH_TAG 0x85F6D6C
#define RVA_GAMEOBJECT_FIND_GAMEOBJECTS_WITH_TAG 0x85F729C
#define RVA_GAMEOBJECT_GET_COMPONENT          0x85F7410 // GetComponent(Type)

// UnityEngine.Transform
#define RVA_TRANSFORM_GET_POSITION     0x8605018
#define RVA_TRANSFORM_SET_POSITION     0x86050E0
#define RVA_TRANSFORM_GET_ROTATION     0x8605308
#define RVA_TRANSFORM_SET_ROTATION     0x86053E0
#define RVA_TRANSFORM_GET_EULER_ANGLES 0x8605280
#define RVA_TRANSFORM_SET_EULER_ANGLES 0x8605368
#define RVA_TRANSFORM_GET_FORWARD      0x8605938
#define RVA_TRANSFORM_GET_UP           0x86057B0
#define RVA_TRANSFORM_GET_RIGHT        0x8605628

// UnityEngine.Object
#define RVA_OBJECT_FIND_OBJECTS_OF_TYPE      0x85FD2C4
#define RVA_OBJECT_FIND_OBJECTS_OF_TYPE_INC  0x85FD378
#define RVA_OBJECT_GET_NAME                  0x85FCEA0
#define RVA_OBJECT_GET_INSTANCE_ID           0x85FCF00

// UnityEngine.Component
#define RVA_COMPONENT_GET_TRANSFORM  0x86031C8
#define RVA_COMPONENT_GET_GAME_OBJECT 0x8603260

// ===================================================================
// Function pointer typedefs
// ===================================================================
typedef UnityVector3 (*WorldToScreenPointFunc)(void* camera, UnityVector3 position);
typedef void* (*CameraGetMainFunc)();
typedef void* (*CameraGetCurrentFunc)();
typedef void* (*GameObjectFindWithTagFunc)(void* str);
typedef void** (*GameObjectFindGameObjectsWithTagFunc)(void* str);
typedef void* (*GameObjectGetComponentFunc)(void* gameObject, void* type);
typedef UnityVector3 (*TransformGetPositionFunc)(void* transform);
typedef void (*TransformSetPositionFunc)(void* transform, UnityVector3 value);
typedef UnityQuaternion (*TransformGetRotationFunc)(void* transform);
typedef void (*TransformSetRotationFunc)(void* transform, UnityQuaternion value);
typedef UnityVector3 (*TransformGetEulerAnglesFunc)(void* transform);
typedef void (*TransformSetEulerAnglesFunc)(void* transform, UnityVector3 value);
typedef UnityVector3 (*TransformGetForwardFunc)(void* transform);
typedef void* (*ComponentGetTransformFunc)(void* component);
typedef void* (*ComponentGetGameObjectFunc)(void* component);
typedef void** (*ObjectFindObjectsOfTypeFunc)(void* type);
typedef void* (*ObjectGetNameFunc)(void* obj);

// ===================================================================
// Global function pointers (initialized at runtime)
// ===================================================================
static intptr_t g_base = 0;

static CameraGetMainFunc CameraGetMain = NULL;
static WorldToScreenPointFunc WorldToScreenPoint = NULL;
static GameObjectFindGameObjectsWithTagFunc FindGameObjectsWithTag = NULL;
static GameObjectFindWithTagFunc FindWithTag = NULL;
static GameObjectGetComponentFunc GetComponent = NULL;
static TransformGetPositionFunc TransformGetPosition = NULL;
static TransformSetPositionFunc TransformSetPosition = NULL;
static TransformGetRotationFunc TransformGetRotation = NULL;
static TransformSetRotationFunc TransformSetRotation = NULL;
static TransformGetEulerAnglesFunc TransformGetEulerAngles = NULL;
static TransformSetEulerAnglesFunc TransformSetEulerAngles = NULL;
static TransformGetForwardFunc TransformGetForward = NULL;
static ComponentGetTransformFunc ComponentGetTransform = NULL;
static ComponentGetGameObjectFunc ComponentGetGameObject = NULL;
static ObjectFindObjectsOfTypeFunc ObjectFindObjectsOfType = NULL;
static ObjectGetNameFunc ObjectGetName = NULL;

// Lấy base address của UnityFramework binary
static intptr_t get_base() {
    if (g_base) return g_base;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char* name = _dyld_get_image_name(i);
        if (strstr(name, "UnityFramework") != NULL) {
            g_base = (intptr_t)_dyld_get_image_vmaddr_slide(i);
            break;
        }
    }
    return g_base;
}

// Lấy function pointer từ RVA offset
static void* rva(uint32_t offset) {
    intptr_t base = get_base();
    if (!base) return NULL;
    return (void*)(base + offset);
}

// Khởi tạo tất cả function pointers
static void init_func_ptrs() {
    static bool inited = false;
    if (inited) return;
    inited = true;
    
    if (!get_base()) return;
    
    CameraGetMain = (CameraGetMainFunc)rva(RVA_CAMERA_GET_MAIN);
    WorldToScreenPoint = (WorldToScreenPointFunc)rva(RVA_CAMERA_WORLD_TO_SCREEN_POINT);
    FindGameObjectsWithTag = (GameObjectFindGameObjectsWithTagFunc)rva(RVA_GAMEOBJECT_FIND_GAMEOBJECTS_WITH_TAG);
    FindWithTag = (GameObjectFindWithTagFunc)rva(RVA_GAMEOBJECT_FIND_WITH_TAG);
    GetComponent = (GameObjectGetComponentFunc)rva(RVA_GAMEOBJECT_GET_COMPONENT);
    TransformGetPosition = (TransformGetPositionFunc)rva(RVA_TRANSFORM_GET_POSITION);
    TransformSetPosition = (TransformSetPositionFunc)rva(RVA_TRANSFORM_SET_POSITION);
    TransformGetRotation = (TransformGetRotationFunc)rva(RVA_TRANSFORM_GET_ROTATION);
    TransformSetRotation = (TransformSetRotationFunc)rva(RVA_TRANSFORM_SET_ROTATION);
    TransformGetEulerAngles = (TransformGetEulerAnglesFunc)rva(RVA_TRANSFORM_GET_EULER_ANGLES);
    TransformSetEulerAngles = (TransformSetEulerAnglesFunc)rva(RVA_TRANSFORM_SET_EULER_ANGLES);
    TransformGetForward = (TransformGetForwardFunc)rva(RVA_TRANSFORM_GET_FORWARD);
    ComponentGetTransform = (ComponentGetTransformFunc)rva(RVA_COMPONENT_GET_TRANSFORM);
    ComponentGetGameObject = (ComponentGetGameObjectFunc)rva(RVA_COMPONENT_GET_GAME_OBJECT);
    ObjectFindObjectsOfType = (ObjectFindObjectsOfTypeFunc)rva(RVA_OBJECT_FIND_OBJECTS_OF_TYPE);
    ObjectGetName = (ObjectGetNameFunc)rva(RVA_OBJECT_GET_NAME);
}

// Tạo đối tượng NSString từ C string
static void* create_nsstring(const char* cstr) {
    return (__bridge void*)[NSString stringWithUTF8String:cstr];
}

// Toán tử Vector3
static UnityVector3 vec3(float x, float y, float z) {
    UnityVector3 v = { x, y, z };
    return v;
}

static UnityVector3 vec3_add(UnityVector3 a, UnityVector3 b) {
    return vec3(a.x + b.x, a.y + b.y, a.z + b.z);
}

static UnityVector3 vec3_sub(UnityVector3 a, UnityVector3 b) {
    return vec3(a.x - b.x, a.y - b.y, a.z - b.z);
}

static UnityVector3 vec3_mul(UnityVector3 a, float s) {
    return vec3(a.x * s, a.y * s, a.z * s);
}

static float vec3_dot(UnityVector3 a, UnityVector3 b) {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

static float vec3_mag(UnityVector3 v) {
    return sqrtf(v.x * v.x + v.y * v.y + v.z * v.z);
}

static UnityVector3 vec3_normalize(UnityVector3 v) {
    float m = vec3_mag(v);
    if (m < 0.0001f) return vec3(0, 0, 0);
    return vec3(v.x / m, v.y / m, v.z / m);
}

static float vec3_dist(UnityVector3 a, UnityVector3 b) {
    return vec3_mag(vec3_sub(a, b));
}

// ===================================================================
// AIMBOT LOGIC
// ===================================================================

// Kiểm tra xem người chơi có đang bắn không
// Dùng hàm IsFireBtnPress() trong UIVerticleViewGameScene
// RVA dump: 0x407AC20 IsFireBtnPress
static bool is_firing() {
    // TODO: Hook IsFireBtnPress hoặc kiểm tra trạng thái nút bắn
    return true; // Tạm thời luôn bật
}

// Lấy tất cả Player objects trong scene
// Dùng Object.FindObjectsOfType với type là Player class
static void** get_all_player_objects(int* outCount) {
    if (!ObjectFindObjectsOfType) return NULL;
    
    // Player class - cần lấy Type từ il2cpp
    // Tạm thời dùng FindGameObjectsWithTag("Player")
    if (!FindGameObjectsWithTag) return NULL;
    
    return NULL; // TODO: hoàn thiện
}

// Hook Camera.WorldToScreenPoint để intercept ESP
static UnityVector3 (*orig_WorldToScreenPoint)(void* _this, UnityVector3 position);
static UnityVector3 replaced_WorldToScreenPoint(void* _this, UnityVector3 position) {
    UnityVector3 result = orig_WorldToScreenPoint(_this, position);
    return result;
}

// Vòng lặp aimbot chính - chạy trên main thread
static void aimbot_tick() {
    if (!AIMBOT_ENABLED) return;
    if (!CameraGetMain || !WorldToScreenPoint) return;
    
    void* camera = CameraGetMain();
    if (!camera) return;
    
    // TODO: 
    // 1. Tìm tất cả enemy players
    // 2. Với mỗi enemy, tính world position của bone mục tiêu
    // 3. Convert world position sang screen position
    // 4. Tính góc deviation từ crosshair
    // 5. Chọn enemy gần crosshair nhất
    // 6. Tính aim direction và apply
    
    // Mô phỏng:
    // - Camera.transform.eulerAngles += delta_aim
}

// Timer chạy aimbot
static void start_aimbot_loop() {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSTimer scheduledTimerWithTimeInterval:0.016
                                           repeats:YES
                                             block:^(NSTimer* t) {
                aimbot_tick();
            }];
        });
    });
}

// ===================================================================
// HOOKING SETUP
// ===================================================================

#pragma GCC diagnostic ignored "-Wobjc-root-class"
@interface FFAimbot : NSObject
+ (void)load;
+ (void)setup;
@end

@implementation FFAimbot

+ (void)load {
    NSLog(@"[FFAimbot] FreeFire MAX Aimbot v2.123.1 loaded");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [FFAimbot setup];
    });
}

+ (void)setup {
    intptr_t base = get_base();
    if (!base) {
        NSLog(@"[FFAimbot] ERROR: Cannot find UnityFramework");
        return;
    }
    NSLog(@"[FFAimbot] UnityFramework base: 0x%llX", (long long)base);
    
    init_func_ptrs();
    
    // Hook Camera.WorldToScreenPoint
    void* target_w2s = (void*)(base + RVA_CAMERA_WORLD_TO_SCREEN_POINT);
    MSHookFunction(target_w2s, (void*)replaced_WorldToScreenPoint, (void**)&orig_WorldToScreenPoint);
    NSLog(@"[FFAimbot] WorldToScreenPoint hooked at: %p", target_w2s);
    
    start_aimbot_loop();
    NSLog(@"[FFAimbot] Aimbot initialized!");
}

@end
