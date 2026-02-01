const Clipboard = {
  mounted() {
    this.handleEvent("clipboard", ({ text }) => {
      navigator.clipboard.writeText(text).then(() => {
        // Optional: Add a visual feedback that the text was copied
        const notification = document.createElement("div");
        notification.textContent = "Copied!";
        notification.className = "fixed bottom-4 right-4 bg-green-500 text-white px-4 py-2 rounded-md shadow-lg";
        document.body.appendChild(notification);

        setTimeout(() => {
          notification.remove();
        }, 2000);
      }).catch(err => {
        console.error("Failed to copy text: ", err);
      });
    });
  }
};

export default Clipboard; 