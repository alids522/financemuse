/// MCP policy engine skeleton (PRD §6.2, §6.3). Pure decision logic —
/// no live MCP server in this pass. The same matrix must be enforced
/// server-side; this client copy is for UI labelling and pre-checks only.
enum McpDecision { autoAllow, approvalRequired, denied }

extension McpDecisionLabel on McpDecision {
  String get label => switch (this) {
        McpDecision.autoAllow => 'auto_allow',
        McpDecision.approvalRequired => 'approval_required',
        McpDecision.denied => 'denied',
      };
}

/// Internal app scopes (PRD §6.2). `admin:*` and `agent_permissions:write`
/// are never available via MCP.
enum McpScope {
  accountsRead,
  transactionsRead,
  transactionsCreate,
  transactionsUpdate,
  transactionsDelete,
  categoriesRead,
  categoriesWrite,
  budgetsRead,
  budgetsWrite,
  forecastsRead,
  forecastsSimulate,
  analyticsRead,
  reportsExport,
  transactionsImport,
  recurringWrite,
  admin,
  agentPermissionsWrite,
}

extension McpScopeName on McpScope {
  String get name => switch (this) {
        McpScope.accountsRead => 'accounts:read',
        McpScope.transactionsRead => 'transactions:read',
        McpScope.transactionsCreate => 'transactions:create',
        McpScope.transactionsUpdate => 'transactions:update',
        McpScope.transactionsDelete => 'transactions:delete',
        McpScope.categoriesRead => 'categories:read',
        McpScope.categoriesWrite => 'categories:write',
        McpScope.budgetsRead => 'budgets:read',
        McpScope.budgetsWrite => 'budgets:write',
        McpScope.forecastsRead => 'forecasts:read',
        McpScope.forecastsSimulate => 'forecasts:simulate',
        McpScope.analyticsRead => 'analytics:read',
        McpScope.reportsExport => 'reports:export',
        McpScope.transactionsImport => 'transactions:import',
        McpScope.recurringWrite => 'recurring:write',
        McpScope.admin => 'admin:*',
        McpScope.agentPermissionsWrite => 'agent_permissions:write',
      };
}

class McpPolicy {
  McpPolicy._();

  /// Default auto-allow caps (PRD §6.3), IDR minor units.
  static const int autoCreateLimitMinor = 1000000; // Rp1.000.000
  static const int autoEditDeltaLimitMinor = 250000; // Rp250.000
  static const Duration approvalExpiry = Duration(minutes: 10);

  /// Evaluate one proposed agent action. Returns the decision; the caller
  /// must still obtain a trusted-UI approval for [McpDecision.approvalRequired]
  /// and must never execute [McpDecision.denied].
  static McpDecision evaluateAction({
    required McpScope scope,
    required bool permissionEnabled,
    int? amountMinor,
    int? deltaMinor,
    bool isTransfer = false,
    bool isBulk = false,
    bool isReconciliationChange = false,
    bool sensitiveFieldChanged = false, // account, type, currency
  }) {
    // admin:* and agent_permissions:write are never available via MCP.
    if (scope == McpScope.admin ||
        scope == McpScope.agentPermissionsWrite) {
      return McpDecision.denied;
    }
    // Read-only scopes: allow when enabled.
    if (scope == McpScope.accountsRead ||
        scope == McpScope.transactionsRead ||
        scope == McpScope.categoriesRead ||
        scope == McpScope.budgetsRead ||
        scope == McpScope.forecastsRead ||
        scope == McpScope.forecastsSimulate ||
        scope == McpScope.analyticsRead) {
      return permissionEnabled
          ? McpDecision.autoAllow
          : McpDecision.denied;
    }
    // Anything else needs the permission switched on first.
    if (!permissionEnabled) return McpDecision.denied;

    switch (scope) {
      case McpScope.transactionsCreate:
        if (isTransfer) return McpDecision.approvalRequired;
        if (amountMinor == null || amountMinor <= 0) {
          return McpDecision.denied; // invalid/negative amounts rejected
        }
        return amountMinor <= autoCreateLimitMinor
            ? McpDecision.autoAllow
            : McpDecision.approvalRequired;
      case McpScope.transactionsUpdate:
        if (isBulk || sensitiveFieldChanged || isReconciliationChange) {
          return McpDecision.approvalRequired;
        }
        final delta = (deltaMinor ?? 0).abs();
        return delta <= autoEditDeltaLimitMinor
            ? McpDecision.autoAllow
            : McpDecision.approvalRequired;
      case McpScope.transactionsDelete:
      case McpScope.categoriesWrite:
      case McpScope.budgetsWrite:
      case McpScope.reportsExport:
      case McpScope.transactionsImport:
      case McpScope.recurringWrite:
        // Deny by default; if enabled, always approval (PRD §6.2).
        return McpDecision.approvalRequired;
      default:
        return McpDecision.denied;
    }
  }
}
