# Required by sip_ua / flutter_webrtc release builds.
# Keeps WebRTC JNI bridge classes from being stripped by R8.

-keep class io.github.webrtc.** { *; }
-keep class com.baseflow.** { *; }
-dontwarn org.webrtc.**
