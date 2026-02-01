const SessionTimeout = {
  mounted() {
    // Get timeout and warning periods from data attributes
    this.timeout = parseInt(this.el.dataset.timeoutSeconds) * 1000;  // Convert to milliseconds
    this.warningPeriod = parseInt(this.el.dataset.warningSeconds) * 1000;

    // Time of last activity (initialize to now)
    this.lastActivity = new Date().getTime();

    // Initialize event listeners for user activity
    this.initActivityListeners();

    // Start checking for inactivity
    this.startInactivityCheck();

    // Listen for manually extended sessions
    this.handleEvent("session-extended", () => {
      this.resetInactivityTimers();
      this.hideWarning();
    });
  },

  initActivityListeners() {
    // Track user activity
    const events = ["mousedown", "mousemove", "keypress", "scroll", "touchstart"];

    // Reset timer on activity
    events.forEach(event => {
      document.addEventListener(event, () => {
        this.lastActivity = new Date().getTime();
        this.hideWarning();
      }, true);
    });
  },

  startInactivityCheck() {
    // Check every 10 seconds for inactivity
    this.checkInterval = setInterval(() => this.checkInactivity(), 10000);
  },

  checkInactivity() {
    const now = new Date().getTime();
    const idleTime = now - this.lastActivity;
    const warningThreshold = this.timeout - this.warningPeriod;

    // If user has been inactive long enough to show warning
    if (idleTime >= warningThreshold) {
      // Calculate time remaining
      const timeLeft = Math.max(0, this.timeout - idleTime);

      // If past timeout, redirect to logout
      if (timeLeft <= 0) {
        window.location.href = "/logout?reason=timeout";
        return;
      }

      // Otherwise show and update warning
      this.showWarning(Math.ceil(timeLeft / 1000));
    }
  },

  showWarning(secondsLeft) {
    // Get warning modal element
    const modal = this.el.querySelector(".session-timeout-modal");
    const countdown = this.el.querySelector("#timeout-countdown");

    // Show warning if not already shown
    if (modal.style.display === "none") {
      modal.style.display = "block";

      // Start countdown timer if not already running
      if (!this.countdownTimer) {
        this.countdownTimer = setInterval(() => {
          secondsLeft -= 1;
          countdown.textContent = secondsLeft;

          if (secondsLeft <= 0) {
            clearInterval(this.countdownTimer);
            window.location.href = "/logout?reason=timeout";
          }
        }, 1000);
      }
    }

    // Update countdown
    countdown.textContent = secondsLeft;
  },

  hideWarning() {
    // Hide the warning
    const modal = this.el.querySelector(".session-timeout-modal");
    modal.style.display = "none";

    // Clear the countdown timer
    if (this.countdownTimer) {
      clearInterval(this.countdownTimer);
      this.countdownTimer = null;
    }
  },

  resetInactivityTimers() {
    // Reset the last activity time
    this.lastActivity = new Date().getTime();

    // Make an API call to extend the server-side session
    fetch("/api/sessions/ping", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content
      },
      body: JSON.stringify({}),
      credentials: "same-origin"
    }).catch(error => console.error("Failed to ping session:", error));
  },

  destroyed() {
    // Clear intervals when component is destroyed
    if (this.checkInterval) {
      clearInterval(this.checkInterval);
    }
    if (this.countdownTimer) {
      clearInterval(this.countdownTimer);
    }
  }
};

export default { SessionTimeout }; 