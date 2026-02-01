import Editor from '@toast-ui/editor';

const EditorHook = {
  mounted() {
    const initialContent = this.el.dataset.content || '';
    const hiddenInput = document.getElementById('entry-content-input');

    this.editor = new Editor({
      el: this.el,
      height: '400px',
      initialEditType: 'wysiwyg',
      previewStyle: 'vertical',
      initialValue: initialContent,
      usageStatistics: false,
      toolbarItems: [
        ['heading', 'bold', 'italic', 'strike'],
        ['hr', 'quote'],
        ['ul', 'ol', 'task'],
        ['table', 'link'],
        ['code', 'codeblock'],
        ['scrollSync']
      ],
      events: {
        change: () => {
          const markdown = this.editor.getMarkdown();
          if (hiddenInput) hiddenInput.value = markdown;
          // Debounced push to LiveView for auto-save
          this.debouncedPush(markdown);
        }
      }
    });

    // Debounce content updates
    this.timeout = null;
    this.debouncedPush = (content) => {
      clearTimeout(this.timeout);
      this.timeout = setTimeout(() => {
        this.pushEvent("update_content", { content });
      }, 500);
    };

    // Handle content updates from server
    this.handleEvent("set_content", ({ content }) => {
      if (this.editor.getMarkdown() !== content) {
        this.editor.setMarkdown(content || '');
      }
    });
  },

  destroyed() {
    if (this.editor) {
      this.editor.destroy();
    }
    clearTimeout(this.timeout);
  }
};

export default EditorHook;
