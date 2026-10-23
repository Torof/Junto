// Untrusted path segments are spliced into junto:// and intent:// links only
// when they are a bare UUID (blocks route redirection and intent-URI injection).
export const UUID_RE = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
