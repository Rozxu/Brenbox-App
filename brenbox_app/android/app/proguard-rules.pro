# flutter_local_notifications — keep the plugin and all its scheduled alarm receivers/helpers
-keep class com.dexterous.** { *; }

# Gson — used by flutter_local_notifications to serialize/deserialize scheduled notification
# details into the PendingIntent extras.  Without these rules R8 strips the generic type
# adapter machinery and the ScheduledNotificationReceiver crashes on deserialization.
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses
-dontwarn sun.misc.**
-keep class com.google.gson.** { *; }
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}

# Firebase / Google Play Services
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Keep all BroadcastReceivers and Services (covers alarm receivers not listed in manifest)
-keep public class * extends android.content.BroadcastReceiver
-keep public class * extends android.app.Service

# Flutter engine entry points
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.**
