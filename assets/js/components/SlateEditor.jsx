import React, { useState, useCallback, useMemo, useEffect, useRef } from 'react';
import { createEditor, Text, Transforms, Editor, Range, Element, Node, Point, Path } from 'slate';
import { Slate, Editable, withReact, ReactEditor, useSlateStatic, useSelected, useFocused } from 'slate-react';
import { withHistory } from 'slate-history';
import Prism from 'prismjs';
import 'prismjs/components/prism-markdown'; // Load markdown language
import 'prismjs/components/prism-css'; // Example: Add other languages if needed in code blocks later
import 'prismjs/components/prism-javascript';
import debounce from 'lodash.debounce'; // Use lodash debounce

// Helper to check if the selection is currently inside a block of a specific type
const isBlockActive = (editor, format) => {
  const [match] = Editor.nodes(editor, {
    match: n => n.type === format,
  });
  return !!match;
};

// Helper to toggle block types (like blockquote)
const toggleBlock = (editor, format) => {
  const isActive = isBlockActive(editor, format);
  Transforms.setNodes(
    editor,
    { type: isActive ? 'paragraph' : format }, // Toggle between paragraph and the target format
    { match: n => Editor.isBlock(editor, n) }
  );
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

// --- Slate Initial Value ---
const initialValue = [
  {
    type: 'paragraph',
    children: [{ text: '' }],
  },
];

// --- Component ---
const SlateEditor = (props) => {
  const {
      initialValue: initialMarkdown = '',
      pushEvent, // Keep for potential future use or different components
      pushEventTo,
      pushEventTarget, // The PID or target selector for pushEventTo
      uniqueId,
      formId
  } = props;

  // Create editor instance
  const editor = useMemo(() => withPlugins(withHistory(withReact(createEditor()))), []);

  // State for Slate's value
  const [value, setValue] = useState(() => deserializeMarkdown(initialMarkdown));

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
		console.log(token, "this is token");

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

  // --- Element Rendering (For block elements like blockquotes) ---
   const renderElement = useCallback(({ attributes, children, element }) => {
       switch (element.type) {
           case 'block-quote': // Matches type set in deserialize
               return <blockquote className="md-blockquote" {...attributes}>{children}</blockquote>;
           case 'paragraph': // Default paragraph
           default:
               // Use div instead of p for simpler line handling in contenteditable
               return <div {...attributes}>{children}</div>;
       }
   }, []);

  // --- Debounced Push Event ---
  // Send raw markdown to LiveView only after a pause
    const pushMarkdownUpdate = useMemo(
        () =>
            debounce((newValue) => {
		    console.log("updating markdown value", newValue);
                const markdown = serializeToMarkdown(newValue);
                const payload = { editorId: uniqueId, markdown: markdown };
		    console.log("markdown value", markdown);

                // --- Update hidden input ALWAYS ---
                const hiddenInputId = `${uniqueId}-hidden-input`; // Assuming convention
                const hiddenInput = document.getElementById(hiddenInputId);
                if (hiddenInput) {
                    hiddenInput.value = markdown;
                    // Dispatch 'input' event might be needed if anything relies on observing it
                    hiddenInput.dispatchEvent(new Event('input', { bubbles: true }));
                } else {
                    console.warn("Hidden input not found for editor:", uniqueId, "Expected ID:", hiddenInputId);
                }

                // --- Push event ONLY if targeted (i.e., for editing) ---
                if (pushEventTarget && pushEventTo) {
                    // Use pushEventTo with the target provided by the parent LC
                    pushEventTo(pushEventTarget, "update_editor_content", payload);
                }
                // No pushEvent needed for the non-targeted (new message) editor

            }, 500), // Debounce time
        [uniqueId, pushEventTo, pushEventTarget] // Dependencies
    );

  // --- onChange Handler ---
  const handleChange = (newValue) => {
    setValue(newValue); // Update internal Slate state
    pushMarkdownUpdate(newValue); // Trigger debounced push to LV
  };


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
    const handleKeyDown = (event) => {
        const { selection } = editor;

        // --- Enter (alone): Submit Form ---
        if (!event.shiftKey && event.key === 'Enter') {
            event.preventDefault(); // IMPORTANT: Prevent inserting newline

            const parentForm = document.getElementById(props.formId);
            const hiddenInputId = `${props.uniqueId}-hidden-input`;
            const hiddenInput = document.getElementById(hiddenInputId);

            if (parentForm && hiddenInput) {
                // 1. Flush any pending debounced updates (might be slightly old state)
                pushMarkdownUpdate.flush();

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

            } else {
                if (!parentForm) console.warn("Submit failed: Could not find parent form:", props.formId);
                if (!hiddenInput) console.warn("Submit failed: Could not find hidden input:", hiddenInputId);
            }
            return; // Handled Enter
        }


        // --- Shift + Enter: Insert Newline / Exit Blockquote ---
        if (event.shiftKey && event.key === 'Enter') {
            event.preventDefault();

            const parentBlockEntry = Editor.above(editor, { /* ... */ });
            if (!parentBlockEntry) { editor.insertText('\n'); return; }
            const [parentBlockNode, parentBlockPath] = parentBlockEntry;

            let isInBlockquote = false;
            let isDirectlyInBlockquote = false; // Is parentBlock the quote itself?
            let blockquotePath = null;

            if (parentBlockNode.type === 'block-quote') {
                isInBlockquote = true;
                isDirectlyInBlockquote = true;
                blockquotePath = parentBlockPath;
            } else {
                const ancestorQuoteEntry = Editor.above(editor, { /* ... */ });
                if (ancestorQuoteEntry) {
                    isInBlockquote = true;
                    blockquotePath = ancestorQuoteEntry[1];
                    // isDirectlyInBlockquote remains false
                }
            }

            if (isInBlockquote) {
                // --- Inside Blockquote Context ---
                const currentLineIsEmpty = Editor.string(editor, parentBlockPath).trim() === '';

                // Exit Condition (Only if in a nested block that's empty)
                if (!isDirectlyInBlockquote && currentLineIsEmpty) {
                    console.log("Shift+Enter on empty nested line in quote: Exiting");
                    Transforms.setNodes(editor, { type: 'paragraph' }, { at: parentBlockPath });
                    try { Transforms.liftNodes(editor, { at: parentBlockPath }); } catch(e){}

                }
                // Initial Line Break (Cursor is directly in Blockquote with just text)
                else if (isDirectlyInBlockquote) {
                     console.log("Shift+Enter directly in blockquote: Wrapping and inserting paragraph");
                      // We need to wrap the existing text in a paragraph,
                      // then insert another paragraph after it.

                      // 1. Wrap current selection's block (the blockquote) content with a paragraph
                      // This might wrap the entire text node content
                      Transforms.wrapNodes(editor,
                           { type: 'paragraph', children: [] },
                           { at: parentBlockPath, match: n => Text.isText(n) } // Match text nodes inside
                           // Careful: This might wrap multiple times if called repeatedly?
                           // Alternative: Get all text, remove nodes, insert single paragraph
                      );

                      // 2. Find the path to the newly wrapped paragraph (should be the first child)
                      const firstChildPath = [...parentBlockPath, 0];

                      // 3. Insert a new paragraph AFTER the wrapped one
                      Transforms.insertNodes(editor,
                          { type: 'paragraph', children: [{ text: '' }] },
                          { at: Path.next(firstChildPath), select: true } // Insert after and select
                      );


                }
                // Subsequent Line Break (Cursor is already in a nested paragraph)
                else {
                     console.log("Shift+Enter in nested paragraph: Splitting node");
                     // Split the current paragraph node
                     Transforms.splitNodes(editor, {
                          at: selection, // Split at cursor
                          match: n => Element.isElement(n) && n.type === 'paragraph', // Match paragraph
                          always: true
                     });
                     // Ensure the new node is a paragraph (splitNodes might inherit type?)
                     // It should already be a paragraph if we split a paragraph.
                     // Transforms.setNodes(editor, { type: 'paragraph' }, { mode: 'lowest' }); // Ensure new node is para
                }
            } else {
                // --- Not inside blockquote: Standard Shift+Enter ---
                console.log("Shift+Enter outside quote: Inserting newline text");
                editor.insertText('\n');
            }

            return; // Handled Shift+Enter
        }

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
    };


  // --- Initial value setting ---
  // Needs to run only once or when initialMarkdown prop changes
  useEffect(() => {
      if (initialMarkdown) {
          const nodes = deserializeMarkdown(initialMarkdown);
          // Prevent infinite loops: Only update if the content differs significantly
          // This simple check might not be perfect
          if (JSON.stringify(value) !== JSON.stringify(nodes)) {
                // Use Transforms.removeNodes and Transforms.insertNodes for safer update
                Transforms.removeNodes(editor, { at: [0] }); // Remove placeholder/old content
                Transforms.insertNodes(editor, nodes, { at: [0] }); // Insert deserialized nodes
                setValue(nodes); // Sync React state (might be redundant if editor change triggers it)
                editor.history = { undos: [], redos: [] };
                Editor.normalize(editor, { force: true });
                // Move cursor to end after initial load (optional)
                Transforms.select(editor, Editor.end(editor, []));
          }
      }
  }, [initialMarkdown, editor]); // Rerun if initialMarkdown changes


  return (
    // Provide the editor object and initial value to the Slate component.
    <Slate editor={editor} initialValue={value} onChange={handleChange}>
       {/* TODO: Add Toolbar here later */}
      <Editable
        renderElement={renderElement}
        renderLeaf={renderLeaf}
        decorate={decorate} // Apply decorations
        placeholder="Type your message..."
        spellCheck
        autoFocus={props.autoFocus}
	onKeyDown={handleKeyDown}
        className="prose prose-sm max-w-none p-2 min-h-[40px] max-h-[200px] overflow-y-auto focus:outline-none" // Match CSS
        id={`slate-editable-${uniqueId}`} // Unique ID for editable area if needed
      />
    </Slate>
  );
};

// --- SLATE PLUGIN for Blockquote Input Rule ---
const withPlugins = (editor) => {
    const { insertText, insertBreak, deleteBackward, normalizeNode } = editor;

    // --- insertText Override ---
    editor.insertText = text => {
        const { selection } = editor;

        // Handle '> ' at the start of a line to convert to blockquote
        if (text === ' ' && selection && Range.isCollapsed(selection)) {
            const { anchor } = selection;
            const block = Editor.above(editor, {
                match: n => Element.isElement(n) && Editor.isBlock(editor, n),
            });

            if (block) {
                const [blockNode, blockPath] = block;
                const start = Editor.start(editor, blockPath);
                const range = { anchor, focus: start };
                const beforeText = Editor.string(editor, range);

                // Check if the block is a paragraph and the line starts with >
                if (blockNode.type === 'paragraph' && beforeText === '>') {
                    Transforms.select(editor, range); // Select '>'
                    Transforms.delete(editor);      // Delete it
                    Transforms.setNodes(        // Convert block to blockquote
                        editor,
                        { type: 'block-quote' },
                        { at: blockPath }       // Apply to the found block path
                    );
                    return; // Don't insert the space
                }
            }
        }

        insertText(text); // Default behavior otherwise
    };

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


    // Helps maintain a consistent structure, e.g., ensuring blockquotes
    // only contain block-level elements like paragraphs (or our divs).
    editor.normalizeNode = entry => {
         const [node, path] = entry;

        // Rule 1: Ensure blockquote children are block elements
        if (Element.isElement(node) && node.type === 'block-quote') {
            let modified = false; // Track if we changed anything in this rule pass
            for (const [child, childPath] of Node.children(editor, path)) {
                if (!Editor.isBlock(editor, child)) {
                     console.warn("Normalizing: Wrapping inline text in blockquote with paragraph", child);
                     Transforms.wrapNodes(editor, { type: 'paragraph', children: child.children || [{text: child.text || ''}] }, { at: childPath });
                     modified = true; // We modified, so normalization needs to re-run
                     // Don't break, check all children in one go if possible? Slate might rerun anyway.
                }
            }
            if (modified) return; // Return early if we modified, let Slate re-normalize
        }
        // ... other normalization rules ...

        normalizeNode(entry); // Call original
     };

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
    if (!markdown) return initialValue;
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
    return nodes.length > 0 ? nodes : initialValue;
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
