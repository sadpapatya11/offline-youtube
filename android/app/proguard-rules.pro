# FIX(proguard): youtubedl-android native lib yükleme ve VideoInfo mapper
# yansıma (reflection) kullandığı için minify/shrink açılırsa bu sınıflar
# korunmalıdır — kurallar olmadan release derlemelerde indirme bozulur.
-keep class com.yausername.youtubedl_android.** { *; }
-keep class com.yausername.ffmpeg.** { *; }
-keep class com.yausername.aria2c.** { *; }
-dontwarn com.yausername.**
