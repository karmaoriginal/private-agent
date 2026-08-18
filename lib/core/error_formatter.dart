/// Maps raw exceptions / API errors to friendly, actionable messages
/// so users understand what happened and what to do next.
class ErrorFormatter {
  static String friendly(Object error) {
    var msg = error.toString().replaceFirst('Exception: ', '').trim();
    final lower = msg.toLowerCase();

    if (msg.contains('401') ||
        lower.contains('unauthorized') ||
        lower.contains('invalid api key') ||
        lower.contains('incorrect api key')) {
      return 'Invalid or expired API key. Check it in Settings.';
    }
    if (msg.contains('429') || lower.contains('rate limit')) {
      return 'The provider is rate limiting requests. Wait a few seconds, '
          'or switch model from the model picker.';
    }
    if (msg.contains('402') || lower.contains('insufficient') && lower.contains('credit')) {
      return 'The provider account has no credit. Top it up or use a free endpoint.';
    }
    if (msg.contains('403') || lower.contains('forbidden')) {
      return 'Access denied (403). The key may not have permission for this model.';
    }
    if (msg.contains('404')) {
      return 'Endpoint not found (404). Check the Base URL in Settings.';
    }
    if (lower.contains('failed host lookup') ||
        lower.contains('socketexception') ||
        lower.contains('connection refused')) {
      return 'No connection. Check your internet and that the Base URL is reachable.';
    }
    if (lower.contains('timeout') || lower.contains('timed out')) {
      return 'The model took too long to respond. Try again or pick a faster model.';
    }
    if (lower.contains('empty response') ||
        lower.contains('finished without a visible answer')) {
      return 'The model returned an empty answer (usually token limit or filters). '
          'Increase Max Tokens in Settings.';
    }
    if (lower.contains('api key is not configured')) {
      return 'No API key configured. Open Settings to add one.';
    }
    return msg;
  }
}
