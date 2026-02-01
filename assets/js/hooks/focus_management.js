export const FocusManagement = {
  mounted() {
    this.handleFocus = () => {
      const successMessage = this.el.querySelector('[data-test-id="success-message"]')
      if (successMessage) {
        successMessage.focus()
      }
    }
    this.handleFocus()
  },
  updated() {
    this.handleFocus()
  }
} 