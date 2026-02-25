import re

with open('lib/main.dart', 'r') as f:
    content = f.read()

# 1. Add import for app_logger.dart
import_statement = "import 'package:fonex/services/app_logger.dart';\n"
if "app_logger.dart" not in content:
    content = content.replace("import 'config.dart';", "import 'config.dart';\nimport 'services/app_logger.dart';")

# 2. Add DebugTerminalScreen widget at the end
terminal_widget = """
// =============================================================================
// DEBUG TERMINAL SCREEN - View App Logs
// =============================================================================
class DebugTerminalScreen extends StatelessWidget {
  const DebugTerminalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Debug Terminal: Logs', style: TextStyle(fontFamily: 'monospace', color: Colors.greenAccent)),
        backgroundColor: Colors.grey[900],
        iconTheme: const IconThemeData(color: Colors.greenAccent),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              AppLogger.clear();
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: AppLogger.logUpdateNotifier,
        builder: (context, _, __) {
          final logs = AppLogger.logs.reversed.toList();
          return ListView.builder(
            itemCount: logs.length,
            padding: const EdgeInsets.all(8),
            itemBuilder: (context, index) {
              return Text(
                logs[index],
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Colors.greenAccent,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
"""
if "class DebugTerminalScreen" not in content:
    content += terminal_widget

# 3. Add hidden access in AboutScreen (Version text)
# Find: Text('Version ${FonexConfig.appVersion}', style: GoogleFonts.inter(...),),
about_pattern = re.compile(r"(Text\(\s*'Version \$\{FonexConfig\.appVersion\}',\s*style: GoogleFonts\.inter\([^)]+\),\s*\),)")
about_replacement = r"""GestureDetector(
                      onLongPress: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const DebugTerminalScreen()));
                      },
                      child: \1
                    ),"""
content = about_pattern.sub(about_replacement, content)

# 4. Add secret code in LockScreen _validatePin
pin_pattern = re.compile(r"(final pin = _pinController\.text\.trim\(\);\n\s*if \(pin\.isEmpty\) \{)")
pin_replacement = r"""\1\n    if (pin == '*#06#' || pin == '*#1234#' || pin == '00000000') {
      _pinController.clear();
      Navigator.push(context, MaterialPageRoute(builder: (_) => const DebugTerminalScreen()));
      return;
    }"""
content = pin_pattern.sub(pin_replacement, content)

# 5. Find and replace debugPrint with AppLogger.log in main.dart
content = re.sub(r"debugPrint\((.*?)\);", r"AppLogger.log(\1);", content)

with open('lib/main.dart', 'w') as f:
    f.write(content)

print("Replaced in main.dart")

# Same for realtime_command_service.dart
with open('lib/services/realtime_command_service.dart', 'r') as f:
    content2 = f.read()

if "app_logger.dart" not in content2:
    content2 = content2.replace("import 'package:supabase_flutter/supabase_flutter.dart';", 
                                 "import 'package:supabase_flutter/supabase_flutter.dart';\nimport 'package:fonex/services/app_logger.dart';")
content2 = re.sub(r"debugPrint\((.*?)\);", r"AppLogger.log(\1);", content2)
content2 = re.sub(r"print\((.*?)\);", r"AppLogger.log(\1);", content2)
with open('lib/services/realtime_command_service.dart', 'w') as f:
    f.write(content2)

# Same for sync_service.dart
with open('lib/services/sync_service.dart', 'r') as f:
    content3 = f.read()

if "app_logger.dart" not in content3:
    content3 = content3.replace("import 'package:http/http.dart'", 
                                 "import 'package:fonex/services/app_logger.dart';\nimport 'package:http/http.dart'")
content3 = re.sub(r"debugPrint\((.*?)\);", r"AppLogger.log(\1);", content3)
content3 = re.sub(r"print\((.*?)\);", r"AppLogger.log(\1);", content3)
with open('lib/services/sync_service.dart', 'w') as f:
    f.write(content3)

print("Done replacing.")
