# بناء IPA من الموبايل — بدون ماك

الخطوات 5 دقايق كلها من المتصفح.

---

## الخطوات

### 1. إنشاء repo على GitHub

- افتح [github.com/new](https://github.com/new) من المتصفح
- Name: `filza-browse` (أو أي اسم)
- **Private** ✓ (مهم — bundle ID حساس)
- اضغط **Create repository**

---

### 2. رفع الملفات

على صفحة الـ repo الفارغة اضغط **uploading an existing file**

ارفع الملفات بالترتيب ده:

**أولاً — المجلد الرئيسي:**
- `FilzaBrowse.xcodeproj/project.pbxproj`

على GitHub web، لرفع ملف داخل مجلد:
اكتب اسم المجلد في خانة الـ path يدوياً قبل اسم الملف.
مثلاً اكتب في خانة filename:
```
FilzaBrowse.xcodeproj/project.pbxproj
```
ثم ارفع محتوى الملف.

**أسهل طريقة — استخدم GitHub CLI أو Working Copy (iOS app):**

#### Working Copy (موصى به على iOS):
1. حمّل [Working Copy](https://workingcopyapp.com) من App Store (مجاني)
2. استورد الـ repo الجديد
3. اسحب مجلد `FilzaBrowse_full` كاملاً للـ repo
4. Commit & Push

#### أو عن طريق GitHub.dev (متصفح):
1. على الـ repo اضغط `.` (نقطة) — هيفتح VS Code في المتصفح
2. اسحب مجلد `FilzaBrowse_full` كاملاً على الـ explorer
3. Commit من الـ sidebar

---

### 3. تشغيل البناء

- اذهب لـ **Actions** tab في الـ repo
- هتلاقي workflow اسمه **Build FilzaBrowse IPA**
- اضغط **Run workflow** ← **Run workflow**
- انتظر ~3-5 دقايق

---

### 4. تحميل الـ IPA

- بعد انتهاء الـ run (علامة ✓ خضراء)
- اضغط على اسم الـ run
- في الأسفل تحت **Artifacts** → اضغط **FilzaBrowse_unsigned_ipa**
- هيتحمل ملف zip — استخرجه للـ IPA

---

### 5. تثبيت الـ IPA

| الطريقة | الخطوات |
|---------|---------|
| **Scarlet** | افتح Scarlet ← My Apps ← + ← اختر الـ IPA |
| **TrollStore** (إذا الجهاز مدعوم) | افتح الـ IPA مباشرة من Files |
| **eSign** | Import ← اختر الـ IPA ← Sign & Install |
| **Sideloadly** (من جهاز ثاني) | drop IPA — لا تغير Bundle ID |

---

## ⚠️ تحذير مهم

بعد التوقيع، تأكد إن bundle ID لسا:
```
com.apple.mobile.MobileHouseArrest
```
أي أداة تغيره بتكسر الـ sandbox escape.

افحص: **Settings → General → VPN & Device Management → اسم التطبيق**

---

## إذا فشل الـ build

افتح الـ run الفاشل في Actions وابحث عن `error:` — أغلب الأخطاء بتكون:

- **"scheme not found"** → تأكد إن مجلد `FilzaBrowse.xcodeproj` موجود في root الـ repo
- **"Build input file cannot be found"** → تأكد إن `FilzaBrowse/ContainerBrowser.swift` موجود
- **signing error** → عادي، الـ workflow مضبوط يتجاهله
