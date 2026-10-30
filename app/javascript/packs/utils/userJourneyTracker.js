import Api from "../Services/Api";

/**
 * User Journey Tracker Utility
 * Provides consistent tracking across all QuickOnboarding pages
 */
export class UserJourneyTracker {
  // Params kept for call-site/hook compatibility, but no longer stored — the tracker
  // writes only to the append-only onboarding_events table and never touches settings.
  // eslint-disable-next-line no-unused-vars
  constructor(setting, setSetting) {}

  /**
   * Save user journey action with context.
   *
   * IMPORTANT: this records to the append-only onboarding_events table — it must
   * NOT re-save the settings object. The previous implementation POSTed the whole
   * `{...setting, userJourney}` to /settings on every breadcrumb, which clobbered
   * feature flags (OTP/SMS) with a stale React snapshot and silently lost the
   * merchant's onboarding selections. Delegating to trackEvent keeps journey data
   * without ever touching settings.
   * @param {string} action - The action performed (e.g., 'button_clicked', 'page_loaded')
   * @param {Object} context - Additional context about the action
   * @param {number} step - Current step in the journey (optional)
   */
  async trackAction(action, context = {}, step = null) {
    const resolvedStep = step || this.extractStepFromContext(context);
    await this.trackEvent(action, {
      step: resolvedStep,
      page: this.getCurrentPage(),
      ...context,
    });
  }

  /**
   * Emit a semantic funnel event to the append-only onboarding_events table.
   * Unlike trackAction (which overwrites settings.userJourney), this never loses
   * prior events and is what powers the support dashboard funnel.
   * Fire-and-forget: analytics must never break the onboarding flow.
   * @param {string} event - Semantic event, e.g. 'onboarding_started', 'features_selected'
   * @param {Object} metadata - Extra context; `step` is hoisted to its own column
   */
  async trackEvent(event, metadata = {}) {
    try {
      await Api.post("/onboarding_events", {
        event,
        step: metadata.step ?? null,
        feature: metadata.feature || "quick-onboarding-v2",
        metadata,
        occurred_at: new Date().toISOString(),
      });
    } catch (error) {
      console.error("Error recording onboarding event:", event, error);
    }
  }

  /**
   * Track page load
   * @param {Object} pageContext - Context about the current page
   */
  async trackPageLoad(pageContext = {}) {
    await this.trackAction("page_loaded", {
      ...pageContext,
      url: window.location.pathname,
    });
  }

  /**
   * Track button clicks
   * @param {string} buttonName - Name/identifier of the button
   * @param {Object} context - Additional context
   */
  async trackButtonClick(buttonName, context = {}) {
    await this.trackAction("button_clicked", {
      buttonName: buttonName,
      ...context,
    });
  }

  /**
   * Track form submissions
   * @param {string} formName - Name/identifier of the form
   * @param {Object} formData - Form data (sanitized)
   * @param {Object} context - Additional context
   */
  async trackFormSubmit(formName, formData = {}, context = {}) {
    await this.trackAction("form_submitted", {
      formName: formName,
      formData: this.sanitizeFormData(formData),
      ...context,
    });
  }

  /**
   * Track navigation events
   * @param {string} from - Source page/component
   * @param {string} to - Destination page/component
   * @param {Object} context - Additional context
   */
  async trackNavigation(from, to, context = {}) {
    await this.trackAction("navigation", {
      from: from,
      to: to,
      ...context,
    });
  }

  /**
   * Track feature activation
   * @param {string} featureName - Name of the feature
   * @param {Object} context - Additional context
   */
  async trackFeatureActivation(featureName, context = {}) {
    await this.trackAction("feature_activated", {
      featureName: featureName,
      ...context,
    });
  }

  /**
   * Track settings changes
   * @param {string} settingName - Name of the setting
   * @param {any} oldValue - Previous value
   * @param {any} newValue - New value
   * @param {Object} context - Additional context
   */
  async trackSettingChange(settingName, oldValue, newValue, context = {}) {
    await this.trackAction("setting_changed", {
      settingName: settingName,
      oldValue: oldValue,
      newValue: newValue,
      ...context,
    });
  }

  /**
   * Track errors
   * @param {string} errorType - Type of error
   * @param {string} errorMessage - Error message
   * @param {Object} context - Additional context
   */
  async trackError(errorType, errorMessage, context = {}) {
    await this.trackAction("error_occurred", {
      errorType: errorType,
      errorMessage: errorMessage,
      ...context,
    });
  }

  /**
   * Track completion of onboarding steps
   * @param {string} stepName - Name of the completed step
   * @param {Object} context - Additional context (can include durationSeconds, totalTimeSeconds)
   */
  async trackStepCompletion(stepName, context = {}) {
    await this.trackAction("step_completed", {
      stepName: stepName,
      ...context,
    });
  }

  /**
   * Track time spent on a step or in the flow (for analytics).
   * Call when user leaves a step or completes onboarding.
   * @param {Object} context - Must include at least one of:
   *   - durationSeconds: time on current step
   *   - totalTimeSeconds: time since quick onboarding was opened
   *   - step: step number (1–4)
   */
  async trackTimeSpent(context = {}) {
    await this.trackAction("time_spent", {
      feature: "quick-onboarding-v2",
      ...context,
    });
  }

  // Helper methods
  getCurrentPage() {
    const path = window.location.pathname;
    if (path.includes("/quick-onboarding/")) {
      return path.split("/quick-onboarding/")[1] || "main";
    }
    return path;
  }

  extractStepFromContext(context) {
    if (context.step) return context.step;
    if (context.currentStep) return context.currentStep;

    // Try to extract step from page name
    const page = this.getCurrentPage();
    const stepMap = {
      "": 1,
      otp: 2,
      billing: 3,
      notifications: 2,
      "partial-payment": 2,
      "limit-cod": 2,
      "cod-fees": 2,
    };

    return stepMap[page] || 1;
  }

  sanitizeFormData(formData) {
    // Remove sensitive information
    const sanitized = { ...formData };
    const sensitiveKeys = ["password", "token", "secret", "key", "api_key"];

    sensitiveKeys.forEach((key) => {
      if (sanitized[key]) {
        sanitized[key] = "[REDACTED]";
      }
    });

    return sanitized;
  }
}

/**
 * Hook to use UserJourneyTracker
 * @param {Object} setting - Current setting object
 * @param {Function} setSetting - Function to update setting
 * @returns {UserJourneyTracker} - Tracker instance
 */
export const useUserJourneyTracker = (setting, setSetting) => {
  return new UserJourneyTracker(setting, setSetting);
};

export default UserJourneyTracker;
