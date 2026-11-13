# kotlinx.serialization keeps its own rules via the library's consumer file.
# BouncyCastle: only the lightweight crypto API is used (no JCA provider lookups).
-dontwarn org.bouncycastle.**
-dontwarn javax.naming.**
-keepattributes *Annotation*, InnerClasses
