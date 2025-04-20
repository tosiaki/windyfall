// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"
import LiveReact from "phoenix_live_react";

import SlateEditor from "./components/SlateEditor";

window.Components = {
   SlateEditor // Make SlateEditor available
   // Add other React components here if needed
};

function debounce(func, wait) {
  let timeout;
  return function executedFunction(...args) {
    const later = () => {
      clearTimeout(timeout);
      func.apply(this, args);
    };
    clearTimeout(timeout);
    timeout = setTimeout(later, wait);
  };
};

const RefocusInput = {
  mounted() {
    this.form = this.el
    this.input = this.form.querySelector('input')
    
    // Clear input on successful submission
    this.handleEvent("sent-message", () => {
      if (this.input) {
        this.input.value = "";
        this.input.focus(); // Refocus after sending
      }
    })

    this.handleEvent("focus-reply-input", () => {
      if (this.input) {
        this.input.focus(); // Focus when reply starts
        // Optional: Select text if desired
        // this.input.select();
      }
    });
  },

  updated() {
     // Ensure we still have the correct input reference if DOM changes
     this.input = this.form.querySelector('input[name="new_message"]');
  }
}

// --- Message Interaction Hook ---
const MessageInteractionHook = {
  mounted() {
    this.messageId = this.el.dataset.messageId;
    this.isUser = this.el.dataset.isUser === "";
    // Find text container reliably. Use a specific data attribute if possible.
    // If not, fallback to class selector (less robust).
    const textElement = this.el.querySelector('.group\\/line') || this.el.querySelector('[data-message-text-content]'); // Add data-message-text-content in template if needed
    this.messageText = textElement ? textElement.innerText.trim() : '';

    this.contextMenuHandler = this.handleContextMenu.bind(this);
    this.touchStartHandler = this.handleTouchStart.bind(this);
    this.touchEndHandler = this.handleTouchEnd.bind(this);
    this.touchMoveHandler = this.handleTouchMove.bind(this);
    this.moreOptionsClickHandler = this.handleMoreOptionsClick.bind(this);
    this.customActionHandler = this.handleCustomAction.bind(this); // Handler for our custom event

    // --- Add Listeners to this.el ---
    this.el.addEventListener('contextmenu', this.contextMenuHandler);
    this.el.addEventListener('touchstart', this.touchStartHandler, { passive: false });
    this.el.addEventListener('touchend', this.touchEndHandler);
    this.el.addEventListener('touchmove', this.touchMoveHandler);

    // Add listener for the "..." button within this element
    this.moreOptionsButton = this.el.querySelector('button[data-action="show_context_menu"]');
    if (this.moreOptionsButton) {
      this.moreOptionsButton.addEventListener('click', this.moreOptionsClickHandler);
    }

    // Listen for the custom event dispatched by the global menu handler
    this.el.addEventListener('message-context-action', this.customActionHandler);

    this.longPressTimeout = null;
    this.touchStartX = 0;
    this.touchStartY = 0;
  },

  destroyed() {
    // --- Remove Listeners ---
    this.el.removeEventListener('contextmenu', this.contextMenuHandler);
    this.el.removeEventListener('touchstart', this.touchStartHandler);
    this.el.removeEventListener('touchend', this.touchEndHandler);
    this.el.removeEventListener('touchmove', this.touchMoveHandler);
    if (this.moreOptionsButton) {
      this.moreOptionsButton.removeEventListener('click', this.moreOptionsClickHandler);
    }
    this.el.removeEventListener('message-context-action', this.customActionHandler);

    if (this.longPressTimeout) {
      clearTimeout(this.longPressTimeout);
    }
  },

  handleContextMenu(event) {
    event.preventDefault();
	  console.log(this.isUser, 'in handle context menu');
    showContextMenu(this.messageId, this.isUser, event.clientX, event.clientY, this.messageText);
  },

  handleTouchStart(event) {
    if (event.touches.length !== 1) return; // Ignore multi-touch

    this.touchStartX = event.touches[0].clientX;
    this.touchStartY = event.touches[0].clientY;

    this.longPressTimeout = setTimeout(() => {
      this.longPressTimeout = null; // Clear ref
      // Long press confirmed - show menu at start position
      showContextMenu(this.messageId, this.isUser, this.touchStartX, this.touchStartY, this.messageText);
      // Optionally prevent default actions like scrolling *after* long press is confirmed
      // Be careful with this, might interfere with scrolling intentions
      // event.preventDefault();
    }, 600); // Long press duration
  },

  handleTouchEnd() {
    if (this.longPressTimeout) {
      clearTimeout(this.longPressTimeout);
      this.longPressTimeout = null;
    }
  },

  handleTouchMove(event) {
     if (!this.longPressTimeout) return; // No long press timer active

     // Check if movement exceeds a threshold (e.g., 10 pixels)
     const threshold = 10;
     const dx = Math.abs(event.touches[0].clientX - this.touchStartX);
     const dy = Math.abs(event.touches[0].clientY - this.touchStartY);

     if (dx > threshold || dy > threshold) {
       // Movement threshold exceeded, cancel long press
       clearTimeout(this.longPressTimeout);
       this.longPressTimeout = null;
     }
  },

  handleMoreOptionsClick(event) {
    const rect = event.currentTarget.getBoundingClientRect();
    showContextMenu(this.messageId, this.isUser, rect.left, rect.bottom + 5, this.messageText);
  },

  // --- Handler for the Custom DOM Event ---
  handleCustomAction(event) {
    const action = event.detail.action;
    console.log(`Hook on message-${this.messageId} received custom event:`, action);
    // Push the event to the LiveComponent managing this hook's element
    this.pushEventTo(this.el, "context_menu_action", { action: action, message_id: this.messageId });
  }
};

const ChatHook = {
  mounted() {
    this.isInitialLoad = true;
    this.isLoading = false;
    this.lastScrollTop = 0;
    this.prevScrollHeight = this.el.scrollHeight;

    // Add debounce method
    this.debounce = (func, wait) => {
      let timeout;
      return (...args) => {
        const context = this;
        clearTimeout(timeout);
        timeout = setTimeout(() => func.apply(context, args), wait);
      };
    };

    // Initial scroll after DOM stabilization
    requestAnimationFrame(() => {
      this.scrollToBottom();
      this.isInitialLoad = false;
    });

    this.el.addEventListener('scroll', this.handleScroll.bind(this));
  },

  handleScroll() {
    // Debounce scroll handler manually
    if (!this.scrollDebounce) {
      this.scrollDebounce = this.debounce(() => {
        if (this.shouldLoadPrevious()) {
          this.loadPreviousMessages();
        }
        this.lastScrollTop = this.el.scrollTop;
      }, 100);
    }
    
    this.scrollDebounce();
  },

  shouldLoadPrevious() {
    return !this.isLoading && 
           this.el.scrollTop < 100 && 
           !this.isInitialLoad;
  },

  async loadPreviousMessages() {
    this.loading = true;
    const preLoadHeight = this.el.scrollHeight;
    
    await this.pushEvent("load-before", {});
    
    // Maintain scroll position
    requestAnimationFrame(() => {
      this.el.scrollTop = this.el.scrollHeight - preLoadHeight;
      this.isLoading = false;
    });
  },

  isNearBottom(threshold = 100) {
    return this.el.scrollTop + this.el.clientHeight + threshold >= this.el.scrollHeight;
  },

  scrollToBottom() {
    this.el.scrollTop = this.el.scrollHeight;
  },

  updated() {
    if (this.isInitialLoad) return;

    const newScrollHeight = this.el.scrollHeight;
    const heightDelta = newScrollHeight - this.prevScrollHeight;
    
    // Preserve position if loading older messages
    if (heightDelta > 0 && this.lastKnownScrollPosition > 0) {
      this.el.scrollTop = this.lastKnownScrollPosition + heightDelta;
    }
    // Auto-scroll if near bottom
    else if (this.isNearBottom(50)) {
      this.scrollToBottom();
    }

    this.prevScrollHeight = newScrollHeight;
    this.isLoading = false;
  },

  destroyed() {
    this.el.removeEventListener('scroll', this.handleScroll);
  },

  debugLog() {
    console.log({
      initialLoad: this.isInitialLoad,
      scrollTop: this.el.scrollTop,
      clientHeight: this.el.clientHeight,
      scrollHeight: this.el.scrollHeight,
      nearBottom: this.isNearBottom()
    });
  }
};

const MouseoverHook = {
  mounted() {
    this.el.addEventListener("mouseover", e => {
      this.pushEventTo(this.el, "mouseover", {});
    });

    this.el.addEventListener("mouseout", e => {
      this.pushEventTo(this.el, "mouseout", {});
    });
  }
};

class ReactionHook {
  constructor(el) {
    this.el = el;
    // Keep IntersectionObserver logic if needed for initial fade-in/scale-in
    this.observer = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          // Apply initial style if needed, but don't re-animate here
          entry.target.style.opacity = "1";
          entry.target.style.transform = "scale(1)";
        }
      });
    }, { threshold: 0.1 });

    this.observer.observe(this.el);
  }

  // Remove the updated method entirely if it only did animation
  // updated() {
  //   // NO animation logic here anymore
  // }

  // Add a method to be called explicitly for animation
  triggerAnimation() {
    const animationType = this.el.dataset.animation; // e.g., "bounce"
    if (animationType === "bounce") {
      // Check if animation is already running to prevent overlap (optional but good)
      if (this.el.getAnimations().length === 0) {
         this.el.animate([
           { transform: 'scale(1)' }, // Start state
           { transform: 'scale(1.05)' }, // Smaller bounce
           { transform: 'scale(1)' } // End state
         ], { duration: 200, easing: 'ease-out' }); // Shorter duration, ease-out
      }
    }
     // Add other animation types if needed
  }

  destroyed() {
    // Clean up observer
    if (this.observer) {
      this.observer.disconnect();
    }
  }
}

const ReactionMenuHook = {
  mounted() {
    // Instantiate the ReactionHook logic (now mainly for observer?)
    this.reactionHook = new ReactionHook(this.el);
    this.debounceTimeout = null; // For debouncing mouseleave

    this.el.addEventListener("mouseenter", (e) => {
      // --- Trigger animation immediately on mouse enter ---
      if (this.reactionHook) {
         this.reactionHook.triggerAnimation();
      }
      // --- End animation trigger ---

      // Clear any pending hide event
      if (this.debounceTimeout) {
         clearTimeout(this.debounceTimeout);
         this.debounceTimeout = null;
      }

      // Push event to server to show the menu
      const messageId = parseInt(this.el.dataset.messageId, 10);
      // Ensure we push *to the element itself* if the event handlers
      // are within the hook's element scope in the template
      this.pushEventTo(this.el.dataset.phxTarget || this.el, "show_reaction_menu", {message_id: messageId});
      // Or if target is parent LiveView:
      // this.pushEvent("show_reaction_menu", {message_id: messageId});
    });

    this.el.addEventListener("mouseleave", (e) => {
       // Debounce hiding to handle quick movements over children
       this.debounceTimeout = setTimeout(() => {
           const messageId = parseInt(this.el.dataset.messageId, 10);
           this.pushEventTo(this.el.dataset.phxTarget || this.el, "hide_reaction_menu", {message_id: messageId});
           // Or this.pushEvent(...)
           this.debounceTimeout = null;
       }, 150); // 150ms delay before hiding
    });
  },

  // No longer need updated here if ReactionHook doesn't use it for animation
  // updated() {
  //   // this.reactionHook.updated(); // Remove this call
  // },

  destroyed() {
    // Call destroyed on the child hook if it exists
    if (this.reactionHook && typeof this.reactionHook.destroyed === 'function') {
       this.reactionHook.destroyed();
    }
    // Remove own listeners if needed (usually handled by LiveView)
    if (this.debounceTimeout) {
      clearTimeout(this.debounceTimeout);
    }
  }
};

const RichTextInputHook = {
  mounted() {
    this.editor = this.el.querySelector('[contenteditable="true"]');
    this.hiddenInput = this.el.querySelector('input[type="hidden"]');
    this.formatMenu = this.el.querySelector('.format-menu');
    this.form = document.getElementById(this.el.dataset.formId);

    // Load initial value (for editing)
    const initialValue = this.el.dataset.initialValue || "";
    if (initialValue) {
      this.editor.innerText = initialValue; // Set raw text initially
      this.parseAndStyleContent(); // Style it
      this.updateHiddenInput(); // Ensure hidden input has value
    }

    this.handleInput = this.handleInput.bind(this);
    this.handleKeydown = this.handleKeydown.bind(this);
    this.handleSelectionChange = debounce(this.handleSelectionChange.bind(this), 100); // Debounce selection change
    this.handleFormatButtonClick = this.handleFormatButtonClick.bind(this);
    this.handlePaste = this.handlePaste.bind(this);

    this.editor.addEventListener('input', this.handleInput);
    this.editor.addEventListener('keydown', this.handleKeydown);
    document.addEventListener('selectionchange', this.handleSelectionChange); // Listen globally
    this.formatMenu.addEventListener('mousedown', this.handleFormatButtonClick); // Use mousedown to prevent blur
    this.editor.addEventListener('paste', this.handlePaste);

    this.adjustHeight(); // Initial height check

    // Focus handling for editing
    this.handleEvent("focus-edit-input", ({message_id}) => {
      // Assuming the editor ID includes the message ID somehow or can be derived
      // This part needs refinement based on actual editor ID structure for edits
      if (this.el.id.includes(`edit-${message_id}`)) { // Example check
         this.editor.focus();
         // Place cursor at the end
         const range = document.createRange();
         const sel = window.getSelection();
         range.selectNodeContents(this.editor);
         range.collapse(false); // Collapse to the end
         sel.removeAllRanges();
         sel.addRange(range);
      }
    });

    // Submit raw markdown on form submission (important!)
    if (this.form) {
      this.form.addEventListener('submit', () => {
        this.updateHiddenInput(); // Ensure latest raw markdown is in hidden input
      });
    }

    // Initial styling if content exists (e.g., editing)
    if (this.editor.textContent.trim() !== "") {
        this.parseAndStyleContent(); // Initial parse/style
        this.updateHiddenInput();
    } else {
       this.adjustHeight(); // Adjust even if empty
    }
    this.hideFormatMenu();
  },

  destroyed() {
    this.editor.removeEventListener('input', this.handleInput);
    this.editor.removeEventListener('keydown', this.handleKeydown);
    document.removeEventListener('selectionchange', this.handleSelectionChange);
    this.formatMenu.removeEventListener('mousedown', this.handleFormatButtonClick);
    this.editor.removeEventListener('paste', this.handlePaste);
    // Remove form listener? Maybe not necessary if form gets removed anyway.
  },

  // --- Event Handlers ---

  handleInput(event) {
    // Triggered after user types, pastes, or formats via execCommand

    // Don't parse/style immediately if it was triggered by our own formatting action
    // This check might need refinement depending on how applyMarkdownFormatting works
    if(event.inputType === 'insertText' || event.inputType === 'insertParagraph' || !event.inputType) {
       // Check cursor position BEFORE parsing/styling
       // const { start, end } = this.getCursorPosition(); // Placeholder

       this.parseAndStyleContent();
       this.updateHiddenInput();
       this.adjustHeight();

       // Attempt to restore cursor position (placeholder)
       // this.setCursorPosition(start, end);
    }
    // Hide menu on input
    this.hideFormatMenu();
  },

  handleKeydown(event) {
    // Handle specific keys like Enter, Backspace, Shift+Enter, Tab?
    // Handle '>' + ' ' for blockquotes
    if (event.key === ' ' && event.target.textContent.endsWith('>')) {
        const selection = window.getSelection();
        const range = selection.getRangeAt(0);
        if (range.startOffset === range.endOffset && range.startContainer === this.editor.lastChild && range.startOffset === this.editor.textContent.length) {
            // Basic check: '>' is the last character typed
            // This is a simplified check, might need refinement for cursor position
            const currentText = this.editor.textContent;
            this.editor.textContent = currentText.slice(0, -1); // Remove '>' visually for now
            this.applyBlockquoteStyle(); // Apply style
            event.preventDefault(); // Prevent space from being added initially
            this.updateHiddenInput();
        }
    }

    // Handle Ctrl+B/I
    if ((event.ctrlKey || event.metaKey) && ['b', 'i'].includes(event.key.toLowerCase())) {
       event.preventDefault();
       const format = event.key.toLowerCase() === 'b' ? 'bold' : 'italic';
       this.applyMarkdownFormatting(format);
       // parseAndStyleContent will be triggered by the input event from execCommand
       return; // Don't process further
    }

    // Allow Shift+Enter for newlines within the same block (contenteditable default)
    // Handle Enter for form submission? Or let LV handle it? Usually Enter submits.
    // If Enter should create a new paragraph INSIDE the editor, more complex handling needed.
    // For chat, Enter typically submits, Shift+Enter makes a newline.
    if (event.key === 'Enter' && !event.shiftKey) {
       event.preventDefault(); // Prevent newline in editor
       // Trigger form submission
       if (this.form) {
         // Ensure hidden input is up-to-date before simulating submit
         this.updateHiddenInput();
         // Simulate button click or use form.requestSubmit()
         const submitButton = this.form.querySelector('button[type="submit"]');
         if (submitButton) {
           submitButton.click();
         } else {
           this.form.requestSubmit(); // Modern alternative
         }
       }
    }
  },

  handleSelectionChange() {
    const selection = window.getSelection();
    // Check if selection is within *this* editor instance and not collapsed
    if (selection.rangeCount > 0 && !selection.isCollapsed && this.editor.contains(selection.anchorNode)) {
        // --- Check if selection is fully inside a styled element ---
        // More complex check needed here to disable menu if inside code block etc.
        // For now, always show if selected.

        const range = selection.getRangeAt(0);
        const rect = range.getBoundingClientRect();
        const editorRect = this.editor.getBoundingClientRect();

        this.formatMenu.style.display = 'flex';
        let topPos = rect.top - editorRect.top + this.editor.scrollTop - this.formatMenu.offsetHeight - 5;
        let leftPos = rect.left - editorRect.left + this.editor.scrollLeft + (rect.width / 2) - (this.formatMenu.offsetWidth / 2);

        // Prevent menu going off top/left
        topPos = Math.max(this.editor.scrollTop, topPos); // Don't go above visible scroll area
        leftPos = Math.max(0, leftPos);
        // Prevent menu going off right
        leftPos = Math.min(leftPos, this.editor.clientWidth - this.formatMenu.offsetWidth);


        this.formatMenu.style.top = `${topPos}px`;
        this.formatMenu.style.left = `${leftPos}px`;
    } else {
        this.hideFormatMenu();
    }
  },

  handleFormatButtonClick(event) {
    event.preventDefault();
    event.stopPropagation(); // Prevent triggering other clicks
    const button = event.target.closest('button[data-format]');
    if (button) {
      const format = button.dataset.format;
      this.applyMarkdownFormatting(format);
      // parseAndStyleContent will be triggered by the input event from execCommand
    }
     this.hideFormatMenu(); // Hide after clicking
  },

   handlePaste(event) {
     event.preventDefault(); // Prevent pasting formatted content directly
     const pastedText = event.clipboardData.getData('text/plain');
     if (text) {
       document.execCommand('insertText', false, pastedText); // Insert as plain text
       // Input event will fire after this, triggering parse/style/update
     }

     event.preventDefault();
     const text = event.clipboardData.getData('text/plain');
     if (text) {
       document.execCommand('insertText', false, text);
       // Input event will fire after this
     }
   },

  // --- Core Logic ---

  parseAndStyleContent() {
    // Preserve cursor/selection (Simplified - Needs proper implementation)
    const selection = window.getSelection();
    let anchorNode = selection.anchorNode;
    let anchorOffset = selection.anchorOffset;
    let focusNode = selection.focusNode;
    let focusOffset = selection.focusOffset;
    let isCollapsed = selection.isCollapsed;

    // --- Get Raw Text ---
    // We iterate through nodes to reconstruct text, preserving newlines better than textContent
    let rawText = '';
    this.editor.childNodes.forEach(node => {
        if (node.nodeType === Node.TEXT_NODE) {
            rawText += node.textContent;
        } else if (node.nodeType === Node.ELEMENT_NODE) {
            // Handle line breaks (e.g., from DIVs or BRs if they exist)
            if (node.tagName === 'BR' || node.tagName === 'DIV') {
                rawText += '\n'; // Represent block elements as newlines
            } else {
                 rawText += node.textContent; // Get text from spans etc.
            }
        }
    });
    // Trim potential trailing newline from last div
    rawText = rawText.replace(/\n$/,'');


    // --- Build new HTML with inline styles ---
    // Note: This simple regex approach WILL break with nesting.
    // A proper parser (like a mini state machine) is needed for robustness.
    let processedHTML = this.escapeHtml(rawText); // Start with escaped raw text

    const formats = [
        // Order matters: apply longer/more specific formats first if possible
        { format: 'strikethrough', regex: /(~~)(.+?)\1/gs, styleClass: 'md-strikethrough', markup: '~~' },
        { format: 'bold', regex: /(\*\*)(.+?)\1/gs, styleClass: 'md-bold', markup: '**' },
        // Italic needs careful regex to avoid matching bold's asterisks
        { format: 'italic', regex: /(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)/gs, styleClass: 'md-italic', markup: '*' }, // Negative lookarounds
        // { format: 'code', regex: /(`)(.+?)\1/gs, styleClass: 'md-code', markup: '`' },
        // Spoilers - keep this logic
        { format: 'spoiler', regex: /(\|\|)(.+?)\1/gs, styleClass: 'md-spoiler', markup: '||' }
    ];

    formats.forEach(({ regex, styleClass, markup }) => {
        processedHTML = processedHTML.replace(regex, (_match, _markupSymbol, content) => {
            // Wrap the *content* in a span, keep markup outside
            // Need to be careful not to double-escape content here if already escaped.
            // Re-escaping safe content is usually harmless.
            const escapedMarkup = this.escapeHtml(markup);
            return `${escapedMarkup}<span class="${styleClass}">${content}</span>${escapedMarkup}`;
            // ^ Note: content already went through initial escapeHtml
        });
    });

     // Handle Blockquotes (very basic - wraps entire line starting with >)
     // This should ideally handle multi-line quotes better.
    //  processedHTML = processedHTML.split('\n').map(line => {
    //      if (line.startsWith('> ')) { // Check for escaped '>'
    //          // Remove '> ' and wrap
    //          return `<div class="md-blockquote">${line.substring(4)}</div>`;
    //      }
    //      return line ? `<div>${line}</div>` : '<div><br></div>'; // Wrap lines in divs for block behavior
    //  }).join(''); // Join lines back (implicitly adds newlines between divs)
    // Replacing line handling with simpler paragraph logic for now
     processedHTML = processedHTML.replace(/^(?:>|\>)\s(.*)$/gm, (match, content) => {
       return `<div class="md-blockquote">${content}</div>`;
     });
     // Wrap remaining lines in divs (or use <p> if preferred) for block layout
     processedHTML = processedHTML.split('\n').map(line => {
        if (!line.startsWith('<div class="md-blockquote">')) {
            return `<div>${line || '<br>'}</div>`; // Wrap non-blockquote lines, add <br> for empty lines
        }
        return line; // Keep blockquote div as is
     }).join('');

    // --- Update innerHTML ---
    // Check if HTML actually changed to avoid unnecessary updates/cursor jumps
    if (this.editor.innerHTML !== processedHTML) {
        this.editor.innerHTML = processedHTML;

        // --- Restore Cursor (Simplified - Placeholder) ---
        // This part is HIGHLY complex and likely requires a dedicated library
        // or intricate DOM traversal to work reliably, especially with nested spans.
        // try { this.restoreSelection(anchorNode, anchorOffset, focusNode, focusOffset, isCollapsed); } catch(e) { console.error("Cursor restore failed", e)}
    }
  },

  updateHiddenInput() {
    // **Crucial:** Reconstruct the raw Markdown from the potentially styled innerHTML.
    // Iterate through nodes, detect styled spans, and add back the Markdown markup.
    let rawMarkdown = '';
    this.editor.childNodes.forEach(node => {
        if (node.nodeType === Node.ELEMENT_NODE) {
             // Handle block elements (like our DIV line wrappers or blockquotes)
            if (node.tagName === 'DIV') {
                if(rawMarkdown !== '') rawMarkdown += '\n'; // Add newline before subsequent divs
                if (node.classList.contains('md-blockquote')) {
                    rawMarkdown += '> ';
                }
                 // Recursively get content from within the div
                rawMarkdown += this.getTextFromNode(node);
            } else if (node.tagName === 'BR') {
                // Should be inside a DIV already based on parseAndStyleContent
                 if(rawMarkdown.slice(-1) !== '\n') rawMarkdown += '\n'; // Add newline for BR if not already there
            } else {
                 // Should not happen with current simple styling logic, but safety:
                 rawMarkdown += this.getTextFromNode(node);
            }
        } else if (node.nodeType === Node.TEXT_NODE) {
            rawMarkdown += node.textContent; // Append text nodes directly
        }
    });

    //console.log("Reconstructed MD:", rawMarkdown); // Debugging

    this.hiddenInput.value = rawMarkdown.trim(); // Trim potentially leading/trailing whitespace/newlines

    // Trigger change event
    this.hiddenInput.dispatchEvent(new Event('input', { bubbles: true }));
  },

  // Helper to recursively get text and re-insert markdown from styled spans
  getTextFromNode(parentNode) {
      let text = '';
      parentNode.childNodes.forEach(node => {
          if (node.nodeType === Node.TEXT_NODE) {
              text += node.textContent;
          } else if (node.nodeType === Node.ELEMENT_NODE) {
              if (node.tagName === 'SPAN') {
                  let markup = '';
                  if (node.classList.contains('md-bold')) markup = '**';
                  else if (node.classList.contains('md-italic')) markup = '*';
                  else if (node.classList.contains('md-strikethrough')) markup = '~~';
                  else if (node.classList.contains('md-code')) markup = '`';
                  else if (node.classList.contains('md-spoiler')) markup = '||';

                  // Get text content of the span itself (might contain nested stuff)
                  const spanContent = this.getTextFromNode(node);
                  text += `${markup}${spanContent}${markup}`;
              } else if (node.tagName === 'BR') {
                 if(text.slice(-1) !== '\n') text += '\n';
              } else {
                  // Recursively get text from other elements if necessary (e.g., nested divs)
                  text += this.getTextFromNode(node);
              }
          }
      });
      return text;
  },

  adjustHeight() {
     this.editor.style.height = 'auto'; // Reset height to calculate natural height
     const scrollHeight = this.editor.scrollHeight;
     // Get max-height from style or use default
     const computedStyle = window.getComputedStyle(this.editor);
     const maxHeight = parseInt(computedStyle.maxHeight, 10) || 200;

     if (scrollHeight > maxHeight) {
       this.editor.style.height = `${maxHeight}px`;
       this.editor.style.overflowY = 'auto';
     } else {
       // Use scrollHeight only if it's greater than minHeight to avoid collapsing too small
       const minHeight = parseInt(computedStyle.minHeight, 10) || 40;
       this.editor.style.height = `${Math.max(scrollHeight, minHeight)}px`;
       this.editor.style.overflowY = 'hidden';
     }
  },

  hideFormatMenu() {
    this.formatMenu.style.display = 'none';
  },

  applyMarkdownFormatting(format) {
    const selection = window.getSelection();
    if (!selection.rangeCount) return;

    const range = selection.getRangeAt(0);
    const selectedText = range.toString();

    let prefix = '', suffix = '';
    // ... (switch case for prefix/suffix) ...
    switch (format) {
      case 'bold': prefix = '**'; suffix = '**'; break;
      case 'italic': prefix = '*'; suffix = '*'; break;
      case 'strikethrough': prefix = '~~'; suffix = '~~'; break;
      case 'code': prefix = '`'; suffix = '`'; break;
      case 'spoiler': prefix = '||'; suffix = '||'; break;
      case 'blockquote':
        this.applyBlockquoteStyle(range); // Handle separately
        return;
      default: return;
    }

    // We will directly insert the markdown using execCommand
    // The 'input' event triggered by this will cause parseAndStyleContent to run
    const alreadyFormatted = selectedText.startsWith(prefix) && selectedText.endsWith(suffix) && selectedText.length >= (prefix.length + suffix.length);

    try {
      if (alreadyFormatted) {
        // Remove formatting by replacing with content
        const unwrappedText = selectedText.slice(prefix.length, -suffix.length);
        document.execCommand('insertText', false, unwrappedText);
      } else {
        // Add formatting
        // Handle empty selection: insert markup, place cursor in middle
        if (range.collapsed) {
          document.execCommand('insertText', false, `${prefix}${suffix}`);
          // Move cursor back into the middle (tricky)
          const currentRange = selection.getRangeAt(0);
          currentRange.setStart(currentRange.startContainer, currentRange.startOffset - suffix.length);
          currentRange.collapse(true); // Collapse to start (which is now middle)
          selection.removeAllRanges();
          selection.addRange(currentRange);

        } else {
          document.execCommand('insertText', false, `${prefix}${selectedText}${suffix}`);
        }
      }
      // Manually trigger input event AFTER execCommand might be needed in some browsers
      //setTimeout(() => this.editor.dispatchEvent(new Event('input', { bubbles: true })), 0);

    } catch (e) {
      console.error("Error applying format:", e);
    }
    this.hideFormatMenu();
  },

  applyBlockquoteStyle(range) {
    // More robust blockquote: Find start of line(s) and insert '> '
    const selection = window.getSelection();
    if (!selection.rangeCount) return;
    if(!range) range = selection.getRangeAt(0); // Use selection if no range passed

    // This is still simplified - doesn't handle multiple selected lines well.
    // A better approach involves iterating through selected block elements.
    const startContainer = range.startContainer;
    const startOffset = range.startOffset;

    // Try to find the start of the current line/block
    let lineStartNode = startContainer;
    let lineStartOffset = 0;
    // Basic walk backwards in text node
    if(lineStartNode.nodeType === Node.TEXT_NODE) {
      let text = lineStartNode.textContent;
      let lastNewline = text.lastIndexOf('\n', startOffset - 1);
      lineStartOffset = lastNewline === -1 ? 0 : lastNewline + 1;
    } else {
      // More complex logic needed for start of element nodes
      lineStartOffset = 0; // Default to start of element
    }

    // Create a new range for insertion
    const insertRange = document.createRange();
    try {
      // Find the actual start node (could be a div wrapper)
      let blockNode = startContainer;
      while(blockNode && blockNode !== this.editor && blockNode.nodeName !== 'DIV') {
        blockNode = blockNode.parentNode;
      }
      if(blockNode && blockNode !== this.editor) {
        insertRange.setStart(blockNode, 0); // Insert at beginning of the div
        insertRange.collapse(true);
        selection.removeAllRanges();
        selection.addRange(insertRange);
        document.execCommand('insertText', false, '> ');
      } else {
        // Fallback if block not found (might insert in wrong place)
        insertRange.setStart(lineStartNode, lineStartOffset);
        insertRange.collapse(true);
        selection.removeAllRanges();
        selection.addRange(insertRange);
        document.execCommand('insertText', false, '> ');
      }
    } catch (e) { console.error("Error applying blockquote", e); }

    // Input event should trigger styling
  },

  // Helper function for escaping HTML
  escapeHtml(unsafe) {
    if (!unsafe) return "";
    return unsafe
           .replace(/&/g, "&")
           .replace(/</g, "<")
           .replace(/>/g, ">")
           .replace(/"/g, "&quot;")
           .replace(/'/g, "'");
  },

  // --- Placeholder functions for cursor/selection management ---
  // --- These require significant implementation effort ---
  getCursorPosition() { /* ... find node and offset ... */ return {start: 0, end: 0}; },
  setCursorPosition(start, end) { /* ... complex DOM/Range manipulation ... */ },
  restoreSelection(anchorNode, anchorOffset, focusNode, focusOffset, isCollapsed) { /* ... even more complex ... */ }


};


const hooks = {
  LiveReact,
  RefocusInput,
  ChatHook,
  MouseoverHook,
  ReactionMenuHook,
  MessageInteractionHook
};

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// Add floating leaves particles
function createLeaf() {
  const leaf = document.createElement('div');
  leaf.className = 'leaf';
  // Use a leaf emoji or potentially an SVG for more control
  leaf.innerHTML = '🍃'; // or '💧' for water drops, or mix? Keep it simple.
  leaf.style.left = Math.random() * 100 + 'vw';
  // Vary duration and delay for more natural movement
  leaf.style.animationDuration = (Math.random() * 10 + 15) + 's'; // 15-25 seconds
  leaf.style.animationDelay = (Math.random() * 5) + 's'; // Start at different times
  // Slightly vary opacity
  leaf.style.opacity = (Math.random() * 0.3 + 0.4); // Opacity between 0.4 and 0.7
  // Vary size slightly
  const scale = Math.random() * 0.4 + 0.8; // Scale between 0.8 and 1.2
  leaf.style.transform = `scale(${scale})`;


  document.body.appendChild(leaf);

  // Remove after animation duration + delay + a buffer
  const duration = parseFloat(leaf.style.animationDuration) * 1000;
  const delay = parseFloat(leaf.style.animationDelay) * 1000;
  setTimeout(() => leaf.remove(), duration + delay + 1000); // Remove slightly after animation ends
}

// Start particle system, respecting reduced motion preferences
if (window.matchMedia("(prefers-reduced-motion: no-preference)").matches) {
  // Create leaves less frequently for better performance
  setInterval(createLeaf, 5000); // Every 5 seconds
  // Create a small initial burst
  for(let i = 0; i < 5; i++) {
     setTimeout(createLeaf, Math.random() * 1000);
  }
}

let observer = new IntersectionObserver((entries) => {
  entries.forEach(entry => {
    if(entry.isIntersecting) {
      this.pushEvent("message_visible", {id: entry.target.dataset.id})
    }
  })
});

document.querySelectorAll('.message').forEach(el => observer.observe(el));

// --- Global Context Menu Variables and Functions ---
const contextMenu = document.getElementById('message-context-menu');
let contextMenuTimeout = null;
let contextTouchStart = null;

// Keep these global functions as they manage the single menu element
function hideContextMenu() {
  if (contextMenu) {
    contextMenu.style.display = 'none';
    contextMenu.removeAttribute('data-message-id'); // Clear messageId when hiding
  }
  document.removeEventListener('mousedown', handleOutsideContextMenuClick);
  document.removeEventListener('touchstart', handleOutsideContextMenuClick);
}

function handleOutsideContextMenuClick(event) {
  if (contextMenu && !contextMenu.contains(event.target)) {
    hideContextMenu();
  }
}

function positionContextMenu(x, y) {
  // ... (positioning logic remains the same) ...
   if (!contextMenu) return;

  const menuWidth = contextMenu.offsetWidth;
  const menuHeight = contextMenu.offsetHeight;
  const screenWidth = window.innerWidth;
  const screenHeight = window.innerHeight;

  let left = x;
  let top = y;

  // Adjust if menu goes off-screen
  if (x + menuWidth > screenWidth) {
    left = screenWidth - menuWidth - 5; // Add small padding
  }
  if (y + menuHeight > screenHeight) {
    top = screenHeight - menuHeight - 5; // Add small padding
  }

  // Ensure menu doesn't go off top/left
  left = Math.max(5, left);
  top = Math.max(5, top);


  contextMenu.style.left = `${left}px`;
  contextMenu.style.top = `${top}px`;
}

function buildContextMenuItems(isUser) {
	console.log(isUser, 'isUser');
  // ... (building items logic remains the same) ...
  const items = [
    { action: 'react', label: 'Add Reaction...', icon: 'hero-face-smile', disabled: true },
    { action: 'reply', label: 'Reply', icon: 'hero-arrow-uturn-left' },
    isUser ? { action: 'edit', label: 'Edit Message', icon: 'hero-pencil' } : null,
    { action: 'copy_text', label: 'Copy Text', icon: 'hero-clipboard' },
    { action: 'copy_link', label: 'Copy Link', icon: 'hero-link' },
    { action: 'share', label: 'Share...', icon: 'hero-share' },
    { type: 'divider' },
    isUser ? { action: 'delete', label: 'Delete Message', icon: 'hero-trash', danger: true } : null,
    !isUser ? { action: 'report', label: 'Report Message', icon: 'hero-flag', danger: true, disabled: true } : null, // Placeholder
  ].filter(Boolean); // Remove null items

  const ul = contextMenu.querySelector('ul') || document.createElement('ul');
  ul.innerHTML = '';
  ul.setAttribute('role', 'menu');

  items.forEach(item => {
    if (item.type === 'divider') {
      const hr = document.createElement('hr');
      ul.appendChild(hr);
    } else {
      const li = document.createElement('li');
      li.setAttribute('role', 'menuitem');
      const button = document.createElement('button');
      button.dataset.action = item.action; // Keep action here for the global listener
      button.disabled = item.disabled || false;

      if (item.icon) {
          const iconSpan = document.createElement('span');
          // Icon class needs to be handled by CSS or Tailwind JIT
          iconSpan.className = `${item.icon} inline-block w-4 h-4 mr-2 align-text-bottom text-gray-500`;
          button.appendChild(iconSpan);
      }

      button.appendChild(document.createTextNode(item.label));

      if (item.danger) {
        button.classList.add('text-red-600', 'hover:bg-red-50', 'hover:text-red-700');
      }
      li.appendChild(button);
      ul.appendChild(li);
    }
  });

  if (!contextMenu.contains(ul)) {
    contextMenu.appendChild(ul);
  }
}

// This function is called by the Hook
function showContextMenu(messageId, isUser, x, y, messageText) {
  if (!contextMenu) return;
  hideContextMenu();

  contextMenu.dataset.messageId = messageId; // Store messageId for the global listener
  // isUser and messageText are mainly for building items and copy action
  buildContextMenuItems(isUser);

  contextMenu.style.display = 'block';
  positionContextMenu(x, y);

  // Store text directly on the menu for the global copy handler
  contextMenu.dataset.messageText = messageText;

  setTimeout(() => {
    document.addEventListener('mousedown', handleOutsideContextMenuClick);
    document.addEventListener('touchstart', handleOutsideContextMenuClick);
  }, 50);
}

// --- Global Context Menu Click Listener (Modified) ---
if (contextMenu) {
  contextMenu.addEventListener('click', (event) => {
    const button = event.target.closest('button[data-action]');
    if (button && !button.disabled) {
      const action = button.dataset.action;
      const messageId = contextMenu.dataset.messageId; // Retrieve the messageId

      if (!messageId) {
        console.error("Global context menu click: messageId missing from menu dataset.");
        hideContextMenu();
        return;
      }

      if (action === 'copy_text') {
        const messageText = contextMenu.dataset.messageText;
        if (messageText) {
          navigator.clipboard.writeText(messageText)
            .then(() => console.log("Text copied"))
            .catch(err => console.error('Failed to copy text: ', err));
        } else {
             console.warn("Copy text action, but no message text found in menu dataset.");
        }
      } else {
        // Find the original message bubble element
        const targetElement = document.getElementById(`message-${messageId}`);
        if (targetElement) {
          // Dispatch a custom event ON THE BUBBLE element
          targetElement.dispatchEvent(new CustomEvent('message-context-action', {
            detail: { action: action },
            bubbles: true // Allow event to bubble up if needed (though hook listens directly)
          }));
          console.log(`Dispatched message-context-action '${action}' on #message-${messageId}`);
        } else {
          console.error(`Global context menu click: Could not find target element #message-${messageId}`);
        }
      }
      hideContextMenu(); // Hide menu after any action
    }
  });
}

// Function to scroll and highlight
function scrollAndHighlightMessage(messageId) {
    const targetElement = document.getElementById(`message-${messageId}`);
    if (targetElement) {
        targetElement.scrollIntoView({ behavior: 'smooth', block: 'center' });

        // Simple highlight: add a class, remove after a delay
        targetElement.classList.add('highlight-message');
        setTimeout(() => {
            targetElement.classList.remove('highlight-message');
        }, 2000); // Highlight duration: 2 seconds
    } else {
        console.warn(`scrollAndHighlightMessage: Element #message-${messageId} not found.`);
    }
}

// Listen for the event pushed from LiveView
window.addEventListener("phx:scroll-to-message", (e) => {
    if (e.detail.id) {
        // Use requestAnimationFrame to ensure DOM is updated after LV changes
        requestAnimationFrame(() => {
             scrollAndHighlightMessage(e.detail.id);
        });
    }
});

// Generic listener for clipboard copy events from LiveView
window.addEventListener("phx:clipboard-copy", event => {
  if (event.detail.content) {
    navigator.clipboard.writeText(event.detail.content)
      .then(() => {
          console.log("Content copied to clipboard:", event.detail.content);
          // Optional: Show a temporary success message/toast to the user
          // e.g., showToast("Link copied!");
      })
      .catch(err => {
          console.error('Failed to copy content: ', err);
          // Optional: Show an error message/toast
          // e.g., showToast("Failed to copy link.", "error");
      });
  }
});

window.addEventListener("js:toggle_spoiler_class", event => {
	console.log("js:toggle_spoiler class event")
    const spoilerElement = document.getElementById(event.detail.id);
    if (spoilerElement) {
        spoilerElement.classList.toggle('revealed');
    }
});

// --- Image Gallery Logic ---
let galleryOverlay = null;
let galleryImage = null;
let galleryImageAlt = null;
let galleryPrevButton = null;
let galleryNextButton = null;
let galleryCloseButton = null;

let currentGalleryImages = [];
let currentGalleryIndex = -1;
let currentGalleryId = null; // ID of the message gallery being viewed

function initializeGallery() {
    galleryOverlay = document.getElementById('image-gallery-overlay');
    galleryImage = document.getElementById('gallery-image');
    galleryImageAlt = document.getElementById('gallery-image-alt'); // For screen reader text
    galleryPrevButton = document.getElementById('gallery-prev');
    galleryNextButton = document.getElementById('gallery-next');
    galleryCloseButton = document.getElementById('gallery-close');

    if (!galleryOverlay || !galleryImage || !galleryPrevButton || !galleryNextButton || !galleryCloseButton) {
        console.error("Gallery elements not found!");
        return;
    }

    // --- Event Listeners ---

    // Delegated listener for opening the gallery
    document.body.addEventListener('click', (event) => {
        const trigger = event.target.closest('[data-gallery-trigger]');
        if (trigger) {
            event.preventDefault();
            openGallery(trigger);
        }
    });

    // Close button
    galleryCloseButton.addEventListener('click', closeGallery);

    // Previous/Next buttons
    galleryPrevButton.addEventListener('click', () => navigateGallery(-1));
    galleryNextButton.addEventListener('click', () => navigateGallery(1));

    // Close on overlay click (but not on image/buttons)
    galleryOverlay.addEventListener('click', (event) => {
        if (event.target === galleryOverlay) { // Only close if clicking the backdrop itself
            closeGallery();
        }
    });

    // Keyboard navigation (added when gallery opens)
}

function openGallery(triggerElement) {
    const galleryDataId = triggerElement.dataset.galleryId;
    const startIndex = parseInt(triggerElement.dataset.imageIndex, 10);
    const galleryContainer = document.getElementById(galleryDataId);

    if (!galleryContainer) {
        console.error(`Gallery data container #${galleryDataId} not found.`);
        return;
    }

    try {
        const imagesData = JSON.parse(galleryContainer.dataset.galleryImages || '[]');
        if (!Array.isArray(imagesData) || imagesData.length === 0) {
            console.error('No valid image data found for gallery:', galleryDataId);
            return;
        }

        currentGalleryImages = imagesData;
        currentGalleryId = galleryDataId; // Store which gallery is open

        // Ensure startIndex is valid
        const validStartIndex = Math.max(0, Math.min(startIndex, currentGalleryImages.length - 1));

        showImage(validStartIndex); // Show the clicked image

        galleryOverlay.classList.remove('hidden'); // Show overlay
        document.body.classList.add('gallery-active'); // Prevent body scroll
        document.addEventListener('keydown', handleGalleryKeydown); // Add keyboard listener

    } catch (e) {
        console.error("Failed to parse gallery data:", e);
    }
}

function showImage(index) {
    if (index < 0 || index >= currentGalleryImages.length) {
        console.warn("Invalid image index requested:", index);
        return;
    }

    currentGalleryIndex = index;
    const imageData = currentGalleryImages[index];

    galleryImage.src = imageData.web_path;
    galleryImage.alt = imageData.filename || 'Gallery image'; // Use filename for alt text
    galleryImageAlt.textContent = galleryImage.alt; // Update hidden text for screen readers

    // Update button states
    galleryPrevButton.disabled = index === 0;
    galleryNextButton.disabled = index === currentGalleryImages.length - 1;
}

function navigateGallery(direction) {
    const newIndex = currentGalleryIndex + direction;
    // Check bounds before showing
    if (newIndex >= 0 && newIndex < currentGalleryImages.length) {
        showImage(newIndex);
    }
}

function closeGallery() {
    if (!galleryOverlay) return; // Guard against errors if not initialized

    galleryOverlay.classList.add('hidden'); // Hide overlay
    document.body.classList.remove('gallery-active'); // Restore body scroll
    document.removeEventListener('keydown', handleGalleryKeydown); // Remove listener

    // Reset state
    currentGalleryImages = [];
    currentGalleryIndex = -1;
    currentGalleryId = null;
    galleryImage.src = ""; // Clear image source
    galleryImage.alt = "";
    galleryImageAlt.textContent = "";
}

function handleGalleryKeydown(event) {
    if (currentGalleryImages.length === 0) return; // Gallery not active

    switch (event.key) {
        case 'ArrowLeft':
            event.preventDefault();
            navigateGallery(-1);
            break;
        case 'ArrowRight':
            event.preventDefault();
            navigateGallery(1);
            break;
        case 'Escape':
            event.preventDefault();
            closeGallery();
            break;
    }
}

// Initialize gallery logic once the DOM is ready
// We might need to wait for LiveView connection or use DOMContentLoaded
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initializeGallery);
} else {
  initializeGallery(); // DOM is already ready
}

// --- End Image Gallery Logic ---

console.log("change succeded 52")
// Listener for custom clipboard event pushed from LiveView (if copy logic stays in LV)
// window.addEventListener("clipboard-copy", event => {
//   if (event.detail.content) {
//     navigator.clipboard.writeText(event.detail.content)
//       .then(() => console.log("Text copied via LV event"))
//       .catch(err => console.error('Failed to copy text via LV event: ', err));
//   }
// });
