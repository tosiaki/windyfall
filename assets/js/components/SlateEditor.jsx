import React, { useState, useCallback, useMemo, useEffect, useRef } from 'react';
import { createPortal } from 'react-dom';
import { createEditor, Text, Transforms, Editor, Range, Element, Node, Point, Path } from 'slate';
import { Slate, Editable, withReact, ReactEditor, useSlateStatic, useSelected, useFocused } from 'slate-react';
import { withHistory } from 'slate-history';
import Prism from 'prismjs';
import 'prismjs/components/prism-markdown'; // Load markdown language
import 'prismjs/components/prism-css'; // Example: Add other languages if needed in code blocks later
import 'prismjs/components/prism-javascript';
import debounce from 'lodash.debounce'; // Use lodash debounce

const initialEmptyValue = [
  {
    type: 'paragraph',
    children: [{ text: '' }],
  },
];

const toggleBlock = (editor, format) => {
  const isActive = isBlockActive(editor, format); // Check if already inside the target format

  // --- Turning OFF the format ---
  if (isActive) {
    // Find the highest-level block of the target format containing the selection
    Transforms.unwrapNodes(editor, {
      match: n =>
        !Editor.isEditor(n) &&
        Element.isElement(n) &&
        n['type'] === format,
      // split: true // Might be needed if unwrapping creates adjacent blocks of same type
    });
    // After unwrapping, the nodes *might* have inherited the old type,
    // explicitly set them back to paragraph.
    Transforms.setNodes(editor, { type: 'paragraph' });

  // --- Turning ON the format ---
  } else {
    // Ensure the node(s) being wrapped are standard blocks first (like paragraphs)
    // This prevents trying to wrap things that shouldn't be (like list-items directly)
    // Note: If selection spans multiple blocks, this might set all to paragraph first.
    Transforms.setNodes(
      editor,
      { type: 'paragraph' },
      // Match only blocks that AREN'T the target format already
      // This prevents accidentally setting a blockquote's type to paragraph before wrapping
      { match: n => Editor.isBlock(editor, n) && (!n['type'] || n['type'] !== format) }
    );

    // Now wrap the paragraph(s) in the target format block
    const block = { type: format, children: [] };
    Transforms.wrapNodes(editor, block);
  }
};

// --- isBlockActive can likely remain as previously revised ---
const isBlockActive = (editor, format) => {
  const { selection } = editor;
  if (!selection) return false;
  const [match] = Editor.nodes(editor, {
    at: Editor.unhangRange(editor, selection),
    match: n => !Editor.isEditor(n) && Element.isElement(n) && n['type'] === format,
  });
  return !!match;
};

// Helper to wrap selected text with Markdown syntax
const wrapSelectionWithMarkdown = (editor, prefix, suffix) => {
  if (!editor.selection) return;

  const { selection } = editor;
  const isCollapsed = selection && Range.isCollapsed(selection);
  const selectedText = Editor.string(editor, selection);

  // Basic toggle check: If selection starts/ends with the markup, remove it
  const alreadyWrapped = selectedText.startsWith(prefix) && selectedText.endsWith(suffix) && selectedText.length >= prefix.length + suffix.length;

  ReactEditor.focus(editor); // Ensure editor has focus

  if (alreadyWrapped) {
    // Remove the wrapping markup
    const unwrappedText = selectedText.slice(prefix.length, selectedText.length - suffix.length);
    // Delete the current selection
    Transforms.delete(editor, { at: selection });
    // Insert the unwrapped text
    Transforms.insertText(editor, unwrappedText, { at: selection.anchor }); // Insert at the original start
  } else {
    // Add wrapping markup
    if (isCollapsed) {
      // If no text selected, insert markup and place cursor in the middle
      Transforms.insertText(editor, `${prefix}${suffix}`);
      // Move selection back inside the markup
      Transforms.move(editor, { distance: suffix.length, unit: 'character', reverse: true });
    } else {
      // Wrap the selected text
      Transforms.insertText(editor, `${prefix}${selectedText}${suffix}`, { at: selection });
    }
  }
   // Trigger an onChange event manually if needed, though Slate usually handles it.
   // editor.onChange(); // May not be necessary
};

// --- Toolbar Button Component (Optional but recommended) ---
const FormatButton = ({ format, icon, editor, children }) => {
  let isActive = false;
  let action = () => {};

  switch (format) {
    case 'bold':
      action = () => wrapSelectionWithMarkdown(editor, '**', '**');
      // isActive check is complex with raw markdown, skipping for now
      break;
    case 'italic':
      action = () => wrapSelectionWithMarkdown(editor, '*', '*');
      // isActive check is complex
      break;
    case 'strikethrough':
      action = () => wrapSelectionWithMarkdown(editor, '~~', '~~');
      // isActive check is complex
      break;
    case 'code':
      action = () => wrapSelectionWithMarkdown(editor, '`', '`');
      // isActive check is complex
      break;
    case 'spoiler':
      action = () => wrapSelectionWithMarkdown(editor, '||', '||');
      // isActive check is complex
      break;
    case 'block-quote':
      action = () => toggleBlock(editor, 'block-quote');
      isActive = isBlockActive(editor, 'block-quote'); // Block types are trackable
      break;
    default:
      break;
  }

  return (
    <button
      type="button" // Important: Prevent form submission
      title={format} // Tooltip text
      className={`format-button ${isActive ? 'active' : ''}`} // Add classes for styling
      onMouseDown={event => {
        event.preventDefault(); // Prevent editor losing focus
        action();
      }}
    >
      {children || icon} {/* Render children (text) or icon */}
    </button>
  );
};

let extendedMarkdownGrammar = Prism.languages.markdown; // Start with base
if (Prism.languages.markdown) {
    extendedMarkdownGrammar = Prism.languages.extend('markdown', {
        'spoiler': {
             pattern: /\|\|(.+?)\|\|/s,
             greedy: true,
             // No 'inside' needed if we don't need to tokenize within spoiler content itself for Prism
        }
        // Add other extensions or overrides here if needed in the future
    });
    console.log("Created extended Prism Markdown Grammar"); // Optional confirmation
} else {
    console.error("Prism Markdown language not loaded before extension attempt.");
    // Fallback? Or assume it's always loaded due to import 'prismjs/components/prism-markdown'
}

// --- Configuration ---
const SYMBOLS = {
  bold: '**',
  italic: '*',
  strikethrough: '~~',
  code: '`',
  spoiler: '||',
};
const MARKS = Object.keys(SYMBOLS);

// --- Component ---
const SlateEditor = (props) => {
  const {
      initialValue: initialValueProp = '',
      uniqueId = 'slate-editor',
      formId,
      hiddenInputName = "new_message",
      autoFocus = false,
      placeholder = "Enter your message..."
  } = props;

  // Create editor instance
  const editor = useMemo(() => withPlugins(withHistory(withReact(createEditor()))), []);

    // Use initialEmptyValue if initialValueProp is truly empty
    const [value, setValue] = useState(() => {
        const deserialized = deserializeMarkdown(initialValueProp);
        // Ensure it's never completely empty, always at least one paragraph
        return deserialized && deserialized.length > 0 ? deserialized : initialEmptyValue;
    });

  // State for toolbar
  const toolbarRef = useRef();
  const [showToolbar, setShowToolbar] = useState(false);
  const [toolbarPosition, setToolbarPosition] = useState({ top: -10000, left: -10000 });
  const [portalContainer, setPortalContainer] = useState(null);

  const hiddenInputRef = useRef(); // Ref for the hidden input

    // --- Find portal container on mount ---
    useEffect(() => {
      // Find the portal root element after the component mounts
      const container = document.getElementById('slate-toolbar-portal-root');
      if (container) {
        setPortalContainer(container);
      } else {
        console.error("Portal root '#slate-toolbar-portal-root' not found in the DOM.");
      }
      // No cleanup needed, the element should persist
    }, []); // Run only once on mount

  // Callback to update hidden input and potentially notify parent LV
  const updateHiddenInput = useCallback((newValue) => {
    const markdownString = serializeToMarkdown(newValue);
    const hiddenInput = hiddenInputRef.current;

    if (hiddenInput) {
      hiddenInput.value = markdownString;
      // Dispatch an 'input' event so LiveView hook detects the change
      hiddenInput.dispatchEvent(new Event('input', { bubbles: true }));
    }
    // Removed pushEvent call - handled by hidden input's event listener in hook
  }, [hiddenInputRef]); // Dependencies

  // --- Decoration Logic (Identifies syntax for styling) ---
  const decorate = useCallback(([node, path]) => {
    const ranges = [];
    if (!Text.isText(node)) {
      return ranges;
    }
        if (!extendedMarkdownGrammar) { // Safety check
            console.error("Extended markdown grammar not available for tokenization.");
            return ranges;
        }
        // Helper to get length of Prism tokens (handles nested content)
        const getLength = token => {
            if (typeof token === 'string') {
                return token.length;
            } else if (typeof token.content === 'string') {
                return token.content.length;
            } else {
                // Recursively sum lengths of nested tokens
                return token.content.reduce((l, t) => l + getLength(t), 0);
            }
        };

    // Tokenize the entire text node's content
    const tokens = Prism.tokenize(node.text, extendedMarkdownGrammar);
    let start = 0;

    // Very basic regex approach for decoration - breaks easily with nesting!
    // PrismJS approach from example is more robust but complex to adapt for visible markup

        for (const token of tokens) {
            const length = getLength(token);
            const end = start + length;

            // If the token is not just a plain string, it has a type
            if (typeof token !== 'string') {
                // Map Prism token types to Slate marks
                let mark = null;
	        let applyMark = false; // Flag to decide if we add a range
                // --- Handle specific token types ---
                switch (token.type) {
                    case 'bold':
                        mark = 'bold';
                        applyMark = true;
                        break;
                    case 'italic':
                        mark = 'italic';
                        applyMark = true;
                        break;
                    case 'strike':
                        // Check inner punctuation length to differentiate ~ from ~~
                        const firstPunctuation = token.content?.find(t => t.type === 'punctuation');
                        if (firstPunctuation && firstPunctuation.content === '~~') {
                            mark = 'strikethrough';
                            applyMark = true;
                        }
                        // If it's single '~', we simply don't set a mark
                        break;
                    case 'code-snippet': // Prism's type for inline code ``
                        mark = 'code';
                        applyMark = true;
                        break;
                    case 'spoiler': // Handle our newly defined token type
                         mark = 'spoiler';
                         applyMark = true;
                         break;
                    // Ignore other types like 'punctuation', 'url', etc.
                    default:
                        break;
                }

                // If we identified a mark to apply for this token
                if (applyMark && mark) {
                    ranges.push({
                        [mark]: true,
                        anchor: { path, offset: start },
                        focus: { path, offset: end },
                    });
                }
            }

            start = end; // Move offset for the next token
        }

    return ranges;
  }, []);


  // --- Leaf Rendering (Applies CSS classes based on decorations) ---
  const renderLeaf = useCallback(({ attributes, children, leaf }) => {
    // Apply basic styling based on marks identified by decorate
    if (leaf.bold) children = <strong>{children}</strong>;
    if (leaf.italic) children = <em>{children}</em>;
    if (leaf.strikethrough || leaf.deleted) children = <s>{children}</s>;
    if (leaf.code) children = <code className="md-code">{children}</code>; // Use class for specific styling
    if (leaf.spoiler) children = <span className="md-spoiler">{children}</span>; // Use class

    return <span {...attributes}>{children}</span>;
  }, []);

  // Function to render elements (like paragraphs, blockquotes)
  const renderElement = useCallback(({ attributes, children, element }) => {
    switch (element.type) {
      case 'block-quote':
        // Use the existing md-blockquote class for styling consistency
        return <blockquote {...attributes} className="md-blockquote">{children}</blockquote>;
      default: // 'paragraph'
        return <p {...attributes}>{children}</p>;
    }
  }, []);

  // --- onChange Handler ---
  const handleChange = useCallback((newValue) => {
    setValue(newValue); // Update internal Slate state
    updateHiddenInput(newValue); // Update hidden input for LV

    const { selection } = editor;
    const toolbarEl = toolbarRef.current; 

    // Logic to show/hide/position the toolbar
    if (!selection || !ReactEditor.isFocused(editor) || Range.isCollapsed(selection) || Editor.string(editor, selection) === '' || !toolbarEl) {
      if (showToolbar) {
        setShowToolbar(false); // Hide if no selection, not focused, collapsed, or empty string selected
      }
      return;
    }

    try {
      const domSelection = window.getSelection();
      if (!domSelection || domSelection.rangeCount === 0) {
         if (showToolbar) setShowToolbar(false);
         return;
      }
      const domRange = domSelection.getRangeAt(0);
      const rect = domRange.getBoundingClientRect();

      // Calculate position relative to the window
      let top = rect.top - toolbarEl.offsetHeight - 5; // Position above selection
      let left = rect.left + (rect.width / 2) - (toolbarEl.offsetWidth / 2); // Center horizontally

      // Basic boundary checks (adjust as needed)
      top = Math.max(5, top); // Prevent going off top
      left = Math.max(5, left); // Prevent going off left
      left = Math.min(left, window.innerWidth - toolbarEl.offsetWidth - 5); // Prevent going off right

      setToolbarPosition({ top, left });
      if (!showToolbar) setShowToolbar(true);

    } catch (error) {
       console.error("Error getting selection rect:", error);
       if (showToolbar) setShowToolbar(false);
    }
  }, [editor, updateHiddenInput, showToolbar]);


  // --- TODO: Implement Toolbar Button Handlers ---
  // These would use Transforms.setNodes, Editor.addMark, Editor.removeMark etc.
  const handleFormat = (format) => {
      if (!editor.selection) return;
      // Example for toggle mark (bold, italic, etc.)
      const isActive = isMarkActive(editor, format);
        if (format === 'blockquote') {
             // Toggle blockquote type
             const newType = isActive ? 'paragraph' : 'block-quote';
             Transforms.setNodes(editor, { type: newType });
        } else {
             // Toggle inline marks
             if (isActive) {
                 Editor.removeMark(editor, format);
             } else {
                 Editor.addMark(editor, format, true);
             }
        }
  };


    // --- KeyDown Handler ---
    const handleKeyDown = useCallback((event) => {
        const { selection } = editor;

        // --- Enter (alone): Submit Form ---
        if (!event.shiftKey && event.key === 'Enter') {
            console.log("Handling Enter for submit");
            event.preventDefault(); // IMPORTANT: Prevent inserting newline

            const parentForm = document.getElementById(formId);
            const hiddenInputId = `${uniqueId}-hidden-input`;
            const hiddenInput = document.getElementById(hiddenInputId);

            if (parentForm && hiddenInput) {
                // 2. Get the ABSOLUTELY current state and serialize it NOW
                const currentRawMarkdown = serializeToMarkdown(editor.children); // Pass current editor state

                // 3. Log for debugging
                console.log("Enter Key: Current Editor State (JSON):", JSON.stringify(editor.children));
                console.log("Enter Key: Serialized Markdown:", currentRawMarkdown);
                console.log("Enter Key: Updating Hidden Input ID:", hiddenInputId);

                // 4. Force update the hidden input value immediately
                hiddenInput.value = currentRawMarkdown;

                // 5. Log value just before submit
                console.log("Enter Key: Hidden input value BEFORE submit:", hiddenInput.value);

                // 6. Submit the form
                console.log("Submitting form...");
                parentForm.requestSubmit();

                // 7. RESET EDITOR STATE
                console.log("Resetting editor state after submit...");
                // Use Transforms to clear content safely
                Transforms.delete(editor, {
                    at: {
                        anchor: Editor.start(editor, []),
                        focus: Editor.end(editor, []),
                    },
                });
                // Ensure the editor contains at least the initial empty block
                // (delete might leave it empty, insert ensures structure)
                 Transforms.insertNodes(editor, initialEmptyValue, { at: [0] });
                 // Select the start of the now empty editor
                 Transforms.select(editor, Editor.start(editor, []));

                // Also reset the React state variable to match
                setValue(initialEmptyValue); // Use the constant

                // Clear undo history after submitting
                editor.history = { undos: [], redos: [] };
                // --- *** END RESET *** ---

            } else {
                if (!parentForm) console.warn("Submit failed: Could not find parent form:", formId);
                if (!hiddenInput) console.warn("Submit failed: Could not find hidden input:", hiddenInputId);
            }
            return; // Handled Enter
        }


        // --- Shift + Enter: Insert Newline / Exit Blockquote ---
        if (event.shiftKey && event.key === 'Enter') {
            event.preventDefault(); // Always prevent default Shift+Enter behavior

            if (!selection) return;

            // Check if we are inside a blockquote
            const [blockquoteMatch] = Editor.nodes(editor, {
                match: n => Element.isElement(n) && n['type'] === 'block-quote',
                mode: 'highest',
            });

            if (blockquoteMatch) {
                // --- Inside a Blockquote ---

                // Find the current lowest block element (likely paragraph)
                const [currentBlockEntry] = Editor.nodes(editor, {
                    match: n => Element.isElement(n) && Editor.isBlock(editor, n),
                    mode: 'lowest',
                });

                if (currentBlockEntry) {
                    const [currentNode, currentPath] = currentBlockEntry;
                    const currentText = Node.string(currentNode);

                    // Check if the current line (lowest block) is empty
                    if (currentText.trim() === '') {
                        // Current line is empty. Now check the previous sibling.
                        let prevNodeIsEmpty = false;
                        let prevPath = null;

                        try {
                             // Attempt to get the previous path
                             prevPath = Path.previous(currentPath);
                             // Try to get the node at the previous path
                             const [prevNode, _] = Editor.node(editor, prevPath);
                             // Check if the previous node is an element and is empty
                             if (Element.isElement(prevNode) && Node.string(prevNode).trim() === '') {
                                 prevNodeIsEmpty = true;
                             }
                        } catch (e) {
                             // Error means path was invalid (e.g., first child) or node didn't exist.
                             // prevNodeIsEmpty remains false.
                             console.log("Shift+Enter: No valid previous empty sibling found.");
                        }

                        // --- EXIT Condition Met (Double Empty Line) ---
                        if (prevNodeIsEmpty && prevPath) { // Ensure prevPath is not null
                            console.log("Shift+Enter on second empty line: Exiting blockquote");
                            // Use withoutNormalizing to perform multiple transforms atomically
                            Editor.withoutNormalizing(editor, () => {
                                // Convert both nodes back to paragraph first
                                Transforms.setNodes(editor, { type: 'paragraph' }, { at: currentPath });
                                Transforms.setNodes(editor, { type: 'paragraph' }, { at: prevPath }); // Use the valid prevPath

                                // Lift the CURRENT node first (as its path changes less immediately)
                                Transforms.liftNodes(editor, { at: currentPath });
                                // Then lift the PREVIOUS node. Its path relative to the original parent
                                // should still be okay even after the sibling was lifted.
                                Transforms.liftNodes(editor, { at: prevPath });
                            });
                        }
                        // --- Insert Newline (Current line empty, BUT previous wasn't OR it's the first line) ---
                        else {
                            console.log("Shift+Enter on first empty line or after non-empty: Splitting node within quote");
                            // Split the current empty paragraph to create a new one below it
                            Transforms.splitNodes(editor, {
                                match: n => Element.isElement(n) && n.type === 'paragraph',
                                always: true,
                            });
                            // Ensure the new node remains a paragraph (splitNodes usually inherits type)
                            // Transforms.setNodes(editor, { type: 'paragraph' }); // Probably redundant
                        }

                    }
                    // --- Insert Newline (Current line is NOT empty) ---
                    else {
                        console.log("Shift+Enter on non-empty line: Splitting node within quote");
                        // Split the current paragraph containing text
                        Transforms.splitNodes(editor, {
                            match: n => Element.isElement(n) && n.type === 'paragraph',
                            always: true, // Split even at start/end of the paragraph
                        });
                        // Ensure the new node remains a paragraph
                        // Transforms.setNodes(editor, { type: 'paragraph' }); // Probably redundant
                    }

                } else {
                    // Edge case: Selection is in blockquote but not within a recognizable block?
                    // Insert a newline character as a fallback.
                    console.log("Shift+Enter: Fallback newline insertion within quote");
                    editor.insertText('\n');
                }

            } else {
                // --- Not inside a blockquote ---
                console.log("Shift+Enter outside quote: Splitting node");
                // Use splitNodes to create a structural break, not just '\n'
                Transforms.splitNodes(editor, {
                    // Split the current block (likely paragraph)
                    match: n => Element.isElement(n) && Editor.isBlock(editor, n),
                    always: true, // Split even at start/end
                });
                 // Optionally ensure the new node is a paragraph if splitNodes doesn't guarantee it
                 // Transforms.setNodes(editor, { type: 'paragraph' });
            }
            return; // Handled Shift+Enter
        } // End Shift+Enter check

        // --- Handle Ctrl/Cmd + B/I (keep existing) ---
        if (!event.shiftKey && (event.ctrlKey || event.metaKey)) {
		switch (event.key) {
		    case 'b':
			event.preventDefault();
			handleFormat('bold'); // Assumes 'bold' is the mark name
			break;
		    case 'i':
			event.preventDefault();
			handleFormat('italic'); // Assumes 'italic' is the mark name
			break;
            // Add more shortcuts
        }


             return; // Make sure to return after handling
        }

        // Default keydown handling will be done by Editable if we don't return
    }, [editor, formId, uniqueId, updateHiddenInput, handleFormat, setValue]);;


  // --- Initial value setting ---
  // Needs to run only once or when initialValue prop changes
  useEffect(() => {
      if (initialValueProp) {
          const nodes = deserializeMarkdown(initialValueProp);
          // Prevent infinite loops: Only update if the content differs significantly
          // This simple check might not be perfect
          if (JSON.stringify(value) !== JSON.stringify(nodes)) {
                // Use Transforms.removeNodes and Transforms.insertNodes for safer update
		 Transforms.removeNodes(editor, {
		     at: { anchor: Editor.start(editor, []), focus: Editor.end(editor, []) },
		     match: () => true, // Match all nodes
		     mode: 'highest'
		 });
                Transforms.insertNodes(editor, nodes, { at: [0] }); // Insert deserialized nodes
                setValue(nodes); // Sync React state (might be redundant if editor change triggers it)
                editor.history = { undos: [], redos: [] };
                Editor.normalize(editor, { force: true });
                // Move cursor to end after initial load (optional)
                Transforms.select(editor, Editor.end(editor, []));
          }
      }
  }, [initialValueProp, editor, value]); // Rerun if initialValue changes

    const renderPlaceholder = useCallback(({ children, attributes }) => {
        // children = the placeholder text string
        // attributes = object containing { 'data-slate-placeholder': true, style: {...}, contentEditable: false, ref: ... }

        // Clone the style object to modify it safely
        const style = { ...attributes.style };

        // Remove Slate's default 'top' positioning
        delete style.top;
        // We can also remove 'left' if we set it via CSS class, otherwise keep Slate's default 'left: 0'.
        // delete style.left;

        // Apply position via CSS class instead of inline style['top']/['left']
        return (
            <span
                {...attributes} // Spread the original attributes (includes data-*, contentEditable, ref)
                style={style}   // Spread the modified style object (without 'top')
                className="slate-placeholder-custom" // Add our custom class
            >
                {children}
            </span>
        );
    }, []); // No dependencies needed for this specific implementation

    const toolbarJsx = (
        <div
            ref={toolbarRef} // Attach ref here
            className="format-menu"
            style={{
                position: 'fixed', // Use fixed position relative to viewport
                top: `${toolbarPosition.top}px`,
                left: `${toolbarPosition.left}px`,
                zIndex: 1000, // High z-index to ensure visibility
                visibility: showToolbar ? 'visible' : 'hidden',
                opacity: showToolbar ? 1 : 0,
                transition: 'opacity 0.1s ease-out, visibility 0.1s ease-out',
                pointerEvents: showToolbar ? 'auto' : 'none',
            }}
            onMouseDown={(e) => e.preventDefault()} // Prevent focus loss
        >
            <FormatButton format="bold" editor={editor}><b>B</b></FormatButton>
            <FormatButton format="italic" editor={editor}><i>I</i></FormatButton>
            <FormatButton format="strikethrough" editor={editor}><s>S</s></FormatButton>
            <FormatButton format="block-quote" editor={editor}>“</FormatButton>
            <FormatButton format="code" editor={editor}>{'</>'}</FormatButton>
            <FormatButton format="spoiler" editor={editor}>||</FormatButton>
        </div>
    );

  return (
    // Provide the editor object and initial value to the Slate component.
    <Slate editor={editor} initialValue={value} onChange={handleChange}>
	  {portalContainer && createPortal(toolbarJsx, portalContainer)}
      <Editable
        renderElement={renderElement}
        renderLeaf={renderLeaf}
        decorate={decorate} // Apply decorations
	placeholder={placeholder}
	renderPlaceholder={renderPlaceholder}
        spellCheck
        autoFocus={autoFocus}
	onKeyDown={handleKeyDown}
        className="prose message-editor-contenteditable min-h-[40px] max-h-[200px] overflow-y-auto px-3 py-2 focus:outline-none" // Match CSS
        id={`slate-editable-${uniqueId || 'editor'}`} // Unique ID for editable area if needed
      />
      <input type="hidden" name={props.hiddenInputName || "new_message"} ref={hiddenInputRef} id={`${uniqueId || 'editor'}-hidden-input`} />
    </Slate>
  );
};

// --- SLATE PLUGIN for Blockquote Input Rule ---
const withPlugins = (editor) => {
    const { insertText, insertBreak, deleteBackward, normalizeNode } = editor;

    // --- insertText Override ---
    editor.insertText = text => {
        const { selection } = editor;

        // Handle '> ' at the start of a *visual line* to convert to blockquote
        if (text === ' ' && selection && Range.isCollapsed(selection)) {
            const { anchor } = selection;
            const blockEntry = Editor.above(editor, {
                match: n => Element.isElement(n) && Editor.isBlock(editor, n),
            });

            if (blockEntry) {
                const [blockNode, blockPath] = blockEntry;
                const blockStart = Editor.start(editor, blockPath);
                // Range from block start to current cursor position
                const rangeBefore = { anchor: blockStart, focus: anchor };
                const textBefore = Editor.string(editor, rangeBefore);

                // Find the start of the current visual line within the block's text
                const lineStartIndex = textBefore.lastIndexOf('\n') + 1; // Handles start of block correctly
                const textOnCurrentLineBeforeCursor = textBefore.substring(lineStartIndex);

                // Check if the *current line* starts with exactly '>'
                if (blockNode.type === 'paragraph' && textOnCurrentLineBeforeCursor === '>') {
                    // Range covering only the '>' character
                    const rangeToDelete = {
                        anchor: Editor.before(editor, anchor, { unit: 'character' }), // Point before the cursor (where '>' is)
                        focus: anchor // Point at the cursor
                    };

                    // Perform transformations atomically
                    Editor.withoutNormalizing(editor, () => {
                         Transforms.delete(editor, { at: rangeToDelete }); // Delete the '>'
                         Transforms.setNodes(editor, // Convert block to blockquote
                           { type: 'block-quote' },
                           { at: blockPath } // Apply to the whole block path
                         );
			    console.log("set the node to block-quote")
                         // Normalization will handle wrapping content in a paragraph later

                        try {
                            // Check the PREVIOUS sibling of the newly converted blockquote
                            const prevPath = Path.previous(blockPath);
                            const [prevNode, _] = Editor.node(editor, prevPath);

                            // If the previous sibling is also a blockquote, merge the current one INTO it.
                            // Note: Merging `blockPath` into `prevPath`
                            if (Element.isElement(prevNode) && prevNode.type === 'block-quote') {
                                console.log("Merging new blockquote (from '>') into previous one.");
                                Transforms.mergeNodes(editor, { at: blockPath });
                                // Normalization will run after this `withoutNormalizing` block anyway
                            }
                        } catch (e) {
                            // Error likely means no previous sibling or it wasn't a blockquote. Ignore.
                        }
                    });
                    return; // Don't insert the space
                }
            }
        }

        insertText(text); // Default behavior otherwise
    }; // End insertText override

    editor.deleteBackward = unit => {
        const { selection } = editor;

        if (selection && Range.isCollapsed(selection)) {
            const point = selection.anchor;

            // Find the block the cursor is directly within
            const blockEntry = Editor.above(editor, {
                match: n => Element.isElement(n) && Editor.isBlock(editor, n),
            });

            if (blockEntry) {
                const [blockNode, blockPath] = blockEntry;
                const startOfBlock = Editor.start(editor, blockPath);
		    console.log(blockPath, blockNode, "checking start of this");

                // Check if cursor is at the start of this immediate block
                if (Point.equals(point, startOfBlock)) {

                    // --- Is the CURRENT block a blockquote? ---
                    if (blockNode.type === 'block-quote') {
			    console.log("passed blocknode blockquote type check");
                        // We are at the start of the blockquote element itself

                        const blockquoteText = Editor.string(editor, blockPath);
                        if (blockquoteText.includes('\n') && blockquoteText.trim() !== '') {
                            // Multi-line: Split and convert first line
                            event.preventDefault(); // Assuming event is available or remove if not
                             const firstNewlineOffset = blockquoteText.indexOf('\n');
                             const splitPoint = Editor.after(editor, startOfBlock, { distance: firstNewlineOffset + 1, unit: 'character' });
                             if (splitPoint) {
                                 try {
                                     Transforms.splitNodes(editor, { at: splitPoint, match: n => n.type === 'block-quote', always: true });
                                     // blockPath now refers to the first line node
                                     Transforms.setNodes(editor, { type: 'paragraph' }, { at: blockPath });
                                 } catch(e) { /* ... error handling ... */ }
                             } else { /* fallback */ Transforms.setNodes(editor, { type: 'paragraph' }, { at: blockPath }); }
                        } else {
                            // Single-line or effectively empty: Convert whole blockquote
                            event.preventDefault();
                            Transforms.setNodes(editor, { type: 'paragraph' }, { at: blockPath });
                        }
                        return; // Handled

                    } else {
			    console.log("checking if inside blockquote", blockEntry);
                        // --- Current block is NOT a blockquote, check if it's INSIDE one ---
                        const blockquoteAncestorEntry = Editor.above(editor, {
                            match: n => Element.isElement(n) && n.type === 'block-quote',
                            at: blockPath, // Search *up* from the current block
                        });

                        if (blockquoteAncestorEntry) {
				console.log("passed ancestor check");
                             // Cursor is at start of a non-blockquote block (e.g., paragraph/div)
                             // that is a child of a blockquote.
                             console.log("Backspace at start of line inside quote (not first line)");
                             event.preventDefault();
                             // Convert this line back to paragraph (might be redundant if already para)
                             Transforms.setNodes(editor, { type: 'paragraph' }, { at: blockPath });
                             // Lift this line out of the quote
                             Transforms.liftNodes(editor, { at: blockPath });
                             return; // Handled
                        }
                        // Else: At start of a normal block not in a quote - allow default backspace
                    }
                } // End if (at start of block)
            } // End if (blockEntry)
        } // End if (selection collapsed)

        // Default backspace behavior
        console.log("Default backspace");
        deleteBackward(unit);
    }; // End deleteBackward


    // --- Enhanced normalizeNode ---
    editor.normalizeNode = entry => {
        const [node, path] = entry;

        // --- Rule 1: Ensure blockquote children are block elements ---
        if (Element.isElement(node) && node.type === 'block-quote') {
            let wrappedChildren = false; // Flag to prevent infinite loops if wrap fails
            for (const [child, childPath] of Node.children(editor, path)) {
                // If a direct child is a Text node (or anything not a block)
                if (Text.isText(child) || !Editor.isBlock(editor, child)) {
                    console.warn("Normalizing: Wrapping non-block child in blockquote with paragraph", child);
                    // Wrap this specific node
                    Transforms.wrapNodes(
                        editor,
                        { type: 'paragraph', children: [] }, // Wrap with a paragraph
                        { at: childPath }                     // Target the specific child path
                    );
                    wrappedChildren = true; // Indicate a change was made
                    // Important: Return *after* finding the first invalid child and wrapping it.
                    // Slate's normalization will re-run until the structure is valid.
                    // Trying to fix multiple invalid children in one pass can be complex.
                    return;
                }
            }
             // If we looped through all children and didn't need to wrap, proceed.
        }

        // --- Rule 2: Ensure top-level editor children are blocks ---
        // (Optional but good practice)
        if (Editor.isEditor(node)) {
            for (const [child, childPath] of Node.children(editor, path)) {
                if (!Editor.isBlock(editor, child)) {
                     console.warn("Normalizing: Wrapping top-level non-block child with paragraph", child);
                     Transforms.wrapNodes(editor, { type: 'paragraph', children: [] }, { at: childPath });
                     return; // Re-normalize after change
                }
            }
        }

        // --- Rule 3: Merge adjacent blockquotes ---
        // We only need to check elements, not text nodes or the editor root
        if (Element.isElement(node) && node.type === 'block-quote') {
            try {
                // Get the path to the *next* sibling node
                const nextPath = Path.next(path);
                // Retrieve the node at the next path. This will error if path is invalid/out of bounds.
                const [nextNode, _] = Editor.node(editor, nextPath);

                // Check if the next sibling exists and is also a blockquote
                if (Element.isElement(nextNode) && nextNode.type === 'block-quote') {
                    console.log("Normalizing: Merging adjacent blockquotes at path", path);
                    // Merge the `nextNode` into the `node` at `path`.
                    // The `nextNode` will be removed after its children are moved.
                    Transforms.mergeNodes(editor, { at: nextPath });
                    // Return early because the structure changed significantly, need to re-run normalization.
                    return;
                }
            } catch (e) {
                // Error likely means no next sibling exists (Path.next was out of bounds
                // or Editor.node failed), which is fine. We just don't merge.
                // console.log("No next sibling blockquote to merge for path", path);
            }
        } // End Rule 3 check


        // Call the original normalizeNode function for other rules or default behavior
        normalizeNode(entry);
    }; // End normalizeNode override

    return editor;
};

// --- Helper: Map Prism types to Slate marks ---
const mapPrismTokenTypeToMark = (prismType) => {
    switch (prismType) {
        case 'bold': return 'bold';
        case 'italic': return 'italic';
        case 'strike': // Prism might use this sometimes?
        case 'deleted': return 'strikethrough'; // Map Prism 'deleted' to our 'strikethrough' mark
        case 'code-snippet': return 'code';
        // Add custom spoiler logic here if Prism doesn't handle ||...||
        // For now, assume decorate handles spoiler separately or Prism is extended
        // If not, decorate needs to find ||...|| itself and add the 'spoiler' mark
        // case 'spoiler': return 'spoiler'; // If Prism handled it
        default: return null; // Ignore other Prism types (url, punctuation, etc.)
    }
};

// --- Helper: Check if mark is active ---
const isMarkActive = (editor, format) => {
    if (!editor.selection) return false;
    const marks = Editor.marks(editor);
    return marks ? marks[format] === true : false;
};

// --- Deserialization Example (assuming nested structure) ---
const deserializeMarkdown = (markdown) => {
    if (!markdown) return initialEmptyValue;
    const lines = markdown.split('\n');
    const nodes = [];
    let currentBlockquoteChildren = null;

    for (const line of lines) {
        if (line.startsWith('> ')) {
            const content = line.substring(2);
            // Child IS A PARAGRAPH
            const paragraph = { type: 'paragraph', children: [{ text: content }] }; // TODO: Parse inline marks
            if (currentBlockquoteChildren === null) currentBlockquoteChildren = [];
            currentBlockquoteChildren.push(paragraph);
        } else {
            if (currentBlockquoteChildren !== null) {
                nodes.push({ type: 'block-quote', children: currentBlockquoteChildren });
                currentBlockquoteChildren = null;
            }
            if (line.trim() !== '') {
                nodes.push({ type: 'paragraph', children: [{ text: line }] }); // TODO: Parse inline marks
            }
        }
    }
    if (currentBlockquoteChildren !== null) {
        nodes.push({ type: 'block-quote', children: currentBlockquoteChildren });
    }
    return nodes.length > 0 ? nodes : initialEmptyValue;
};

// --- Serialization Example (assuming nested structure) ---
const serializeToMarkdown = (nodes) => {
    // Add checks for nodes being an array
    if (!Array.isArray(nodes)) {
        console.error("serializeToMarkdown received non-array:", nodes);
        return "";
    }
    return nodes.map(node => {
        // Add check for Text node
        if (Text.isText(node)) {
            let text = node.text || ""; // Default to empty string
            // Apply marks...
            if (node.code) text = `\`${text}\``;
            if (node.strikethrough) text = `~~${text}~~`;
            if (node.bold) text = `**${text}**`;
            if (node.italic) text = `*${text}*`;
            if (node.spoiler) text = `||${text}||`;
            return text;
        }

        // Add check for children property before recursing
        const childrenString = node.children ? serializeToMarkdown(node.children) : "";

        switch (node.type) {
            case 'block-quote':
                return childrenString
                        .split('\n')
                        .filter(line => line.trim() !== '')
                        .map(line => `> ${line}`)
                        .join('\n') + (childrenString.trim() === '' ? '' : '\n'); // Add newline only if content exists
            case 'paragraph':
            default:
                // Return newline only if there was actual content
                return childrenString.trim() === '' ? '' : `${childrenString.trim()}\n`;
        }
    }).join('').trim(); // Trim final result
};

export default SlateEditor;
