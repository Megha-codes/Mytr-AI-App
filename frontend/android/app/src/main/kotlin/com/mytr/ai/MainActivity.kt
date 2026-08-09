package com.example.frontend

import io.flutter.embedding.android.FlutterFragmentActivity

// The health plugin's Android side needs a Fragment-based Activity Result API
// (ActivityResultLauncher) to show the actual Health Connect permission
// screen — the plain FlutterActivity this was before doesn't support that,
// which is what caused the native "Permission launcher not found" log and
// the silent (no UI, no exception) permission failure. FlutterFragmentActivity
// is a drop-in, officially-supported replacement built for exactly this.
class MainActivity : FlutterFragmentActivity()
