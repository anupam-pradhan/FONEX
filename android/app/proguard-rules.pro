# Suppress R8 missing class warnings for Google Tink cryptography dependencies
# These annotations are compile-only and safely ignored at runtime

-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
-keep class com.google.crypto.tink.** { *; }

-dontwarn com.google.api.client.**
-dontwarn org.joda.time.**
