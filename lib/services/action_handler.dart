import 'package:http/http.dart' as http;
import '../models/agent_action.dart';
import '../models/chat_message.dart';
import 'app_launcher_service.dart';
import 'contacts_service.dart';
import 'communication_service.dart';
import 'alarm_service.dart';
import 'system_control_service.dart';
import 'shizuku_service.dart';
import 'screen_automation_service.dart';
import 'task_executor.dart';
import 'ai_service.dart';
import 'search_service.dart';
import 'camofox_service.dart';
import 'sandbox_service.dart';
import 'mcp_service.dart';

class ActionHandler {
  final AppLauncherService _appLauncher = AppLauncherService();
  final ContactsService _contacts = ContactsService();
  final CommunicationService _communication = CommunicationService();
  final AlarmService _alarm = AlarmService();
  final SystemControlService _systemControl = SystemControlService();
  final ShizukuService _shizuku = ShizukuService();
  final ScreenAutomationService _screenAutomation = ScreenAutomationService();
  final SearchService _search = SearchService();
  final SandboxService _sandbox = SandboxService();
  final McpService _mcp = McpService();

  ShizukuService get shizuku => _shizuku;
  ScreenAutomationService get screenAutomation => _screenAutomation;
  SearchService get search => _search;
  CamofoxService get camofox => _search.camofox;
  SandboxService get sandbox => _sandbox;
  McpService get mcp => _mcp;

  bool _integrationsInitialized = false;

  /// The currently running task executor, if any
  TaskExecutor? _currentExecutor;

  Future<void> _ensureIntegrations() async {
    if (_integrationsInitialized) return;
    _integrationsInitialized = true;
    await _search.init();
    await _sandbox.init();
    await _mcp.init();
  }

  /// Execute an action and return the result
  Future<AgentActionResult> execute(
    AgentAction action, {
    AiService? aiService,
    void Function(String)? onProgress,
  }) async {
    try {
      String result;

      switch (action.action) {
        case 'open_app':
          result = await _appLauncher.openApp(
            action.params['app_name'] as String? ?? '',
          );
          break;

        case 'launch_package':
          final packageName = action.params['package_name'] as String? ?? '';
          result = await _appLauncher.openPackage(packageName);
          break;

        case 'make_call':
          result = await _communication.makeCall(
            contactName: action.params['contact_name'] as String?,
            phoneNumber: action.params['phone_number'] as String?,
          );
          break;

        case 'send_sms':
          result = await _communication.sendSms(
            contactName: action.params['contact_name'] as String?,
            phoneNumber: action.params['phone_number'] as String?,
            message: action.params['message'] as String? ?? '',
          );
          break;

        case 'search_contact':
          result = await _contacts.searchAndFormat(
            action.params['query'] as String? ?? '',
          );
          break;

        case 'set_alarm':
          result = await _alarm.setAlarm(
            hour: (action.params['hour'] as num?)?.toInt() ?? 0,
            minute: (action.params['minute'] as num?)?.toInt() ?? 0,
            label: action.params['label'] as String?,
          );
          break;

        case 'set_timer':
          result = await _alarm.setTimer(
            seconds: (action.params['seconds'] as num?)?.toInt() ?? 60,
            label: action.params['label'] as String?,
          );
          break;

        case 'set_volume':
          result = await _systemControl.setVolume(
            (action.params['level'] as num?)?.toInt() ?? 50,
          );
          break;

        case 'set_brightness':
          result = await _systemControl.setBrightness(
            (action.params['level'] as num?)?.toInt() ?? 50,
          );
          break;

        case 'run_adb_command':
          result = await _shizuku.runCommand(
            action.params['command'] as String? ?? '',
          );
          break;

        case 'send_email':
          result = await _communication.sendEmail(
            to: action.params['to'] as String? ?? '',
            subject: action.params['subject'] as String?,
            body: action.params['body'] as String?,
          );
          break;

        case 'open_url':
          result = await _appLauncher.openUrl(
            action.params['url'] as String? ?? '',
          );
          break;

        // ─── Web & knowledge tools ────────────────────────────

        case 'web_search':
          await _ensureIntegrations();
          final query = action.params['query'] as String? ?? '';
          onProgress?.call('Searching the web: "$query"');
          result = await _search.search(query);
          break;

        case 'browse_page':
          await _ensureIntegrations();
          final url = action.params['url'] as String? ?? '';
          onProgress?.call('Opening page: $url');
          if (_search.provider == 'camofox' && _search.camofox.isConfigured) {
            result = await _search.camofox.openPage(url);
          } else {
            // Lightweight fallback: plain HTTP GET + tag stripping.
            result = await _fetchPlainText(url);
          }
          break;

        // ─── Remote sandbox ───────────────────────────────────

        case 'run_code':
          await _ensureIntegrations();
          final command = action.params['command'] as String? ?? '';
          final language = action.params['language'] as String? ?? 'bash';
          onProgress?.call('Running in sandbox: $command');
          result = await _sandbox.execute(command, language: language);
          break;

        // ─── MCP plugins ──────────────────────────────────────

        case 'mcp_call':
          await _ensureIntegrations();
          final server = action.params['server'] as String? ?? '';
          final tool = action.params['tool'] as String? ?? '';
          final args =
              (action.params['arguments'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{};
          onProgress?.call('Calling MCP tool $tool on $server');
          result = await _mcp.callTool(server, tool, args);
          break;

        // ─── Screen Automation Actions ────────────────────────

        case 'read_screen':
          result = await _screenAutomation.getScreenDescription();
          break;

        case 'click_element':
          final text = action.params['text'] as String? ?? '';
          final success = await _screenAutomation.clickByText(text);
          result = success ? 'Clicked "$text"' : 'Could not find "$text" to click';
          break;

        case 'type_on_screen':
          final text = action.params['text'] as String? ?? '';
          final hint = action.params['field_hint'] as String?;
          final success = await _screenAutomation.typeText(text, fieldHint: hint);
          result = success ? 'Typed "$text"' : 'Could not type into field';
          break;

        case 'scroll_screen':
          final direction = action.params['direction'] as String? ?? 'down';
          final success = await _screenAutomation.scroll(direction);
          result = success ? 'Scrolled $direction' : 'Could not scroll';
          break;

        case 'press_back':
          final success = await _screenAutomation.pressBack();
          result = success ? 'Pressed back' : 'Could not press back';
          break;

        // ─── Multi-Step Task Execution ────────────────────────

        case 'execute_task':
          final goal = action.params['goal'] as String? ?? action.response;
          if (aiService == null) {
            result = 'AI service not available for task execution.';
            break;
          }
          _currentExecutor = TaskExecutor(
            aiService: aiService,
            screenService: _screenAutomation,
            appLauncher: _appLauncher,
            shizukuService: _shizuku,
            onProgress: onProgress,
          );
          result = await _currentExecutor!.executeTask(goal);
          _currentExecutor = null;
          break;

        default:
          result = action.response;
      }

      return AgentActionResult(
        actionType: action.action,
        success: true,
        details: result,
      );
    } catch (e) {
      return AgentActionResult(
        actionType: action.action,
        success: false,
        details: 'Error: $e',
      );
    }
  }

  /// Minimal HTML -> text for browse_page when CamoFox is not configured.
  Future<String> _fetchPlainText(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      throw Exception('Invalid URL: $url');
    }
    final response = await http
        .get(uri, headers: {'User-Agent': 'PrivateAgent/1.0'})
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode} fetching $url');
    }
    var text = response.body;
    text = text.replaceAll(
      RegExp(r'<script[\s\S]*?</script>', caseSensitive: false),
      ' ',
    );
    text = text.replaceAll(
      RegExp(r'<style[\s\S]*?</style>', caseSensitive: false),
      ' ',
    );
    text = text.replaceAll(RegExp(r'<[^>]+>'), ' ');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    const maxChars = 8000;
    if (text.length > maxChars) {
      text = '${text.substring(0, maxChars)}...[truncated]';
    }
    return text;
  }

  /// Cancel the currently running task
  void cancelTask() {
    _currentExecutor?.cancel();
  }
}
