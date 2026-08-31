// Interactive Yanmo demo: a working editor, toolbar, and live preview that
// mirror the Mac app. Markdown rendering covers the GFM subset the app renders.

(() => {
  const readingSpeedWPM = 200;
  const textPlaceholder = "text";

  const sampleDocument = [
    "# Write in Markdown. See it as you type.",
    "",
    "Yanmo is a native macOS editor for people who prefer **simple files** and a *focused* workspace.",
    "",
    "## Built for everyday documents",
    "",
    "- Preview changes while you write.",
    "- Keep Markdown and images together on your Mac.",
    "- Start quickly with reusable templates and themes.",
    "- Export clean HTML or PDF when the document is ready.",
    "",
    "- [x] Try the toolbar above",
    "- [ ] Type your own Markdown",
    "",
    "> Your files stay in the folders you choose.",
    "",
    "```markdown",
    "# A clear heading",
    "",
    "Write once. Preview immediately. Export when ready.",
    "```",
    "",
    "Learn more at [yanmo.app](https://yanmo.app).",
    "",
    "| Feature | Included |",
    "| --- | --- |",
    "| Side by side editor | ✓ |",
    "| Live preview | ✓ |",
    "| HTML & PDF export | ✓ |",
    ""
  ].join("\n");

  // Markdown → HTML

  const escapeHTML = (text) => text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");

  const safeURL = (url) => (/^\s*(javascript|vbscript|data|file):/i.test(url) ? "" : url.trim());

  function renderInline(raw) {
    const codeSpans = [];

    const withoutCode = raw.replace(/(`+)([^`]+?)\1/g, (match) => {
      codeSpans.push(match.slice(1, -1));
      return `\u0000${codeSpans.length - 1}\u0000`;
    });

    const html = escapeHTML(withoutCode)
      .replace(/(!?)\[([^\]]*)\]\(([^)]*)\)/g, (match, bang, label, url) => {
        const safe = safeURL(url);
        if (!safe) {
          return "";
        }
        return bang ? `<img src="${safe}" alt="${label}">` : `<a href="${safe}">${label}</a>`;
      })
      .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
      .replace(/__([^_]+)__/g, "<strong>$1</strong>")
      .replace(/\*([^*\n]+)\*/g, "<em>$1</em>")
      .replace(/(?<![\w_])_([^_\n]+?)_(?![\w_])/g, "<em>$1</em>")
      .replace(/~~([^~]+)~~/g, "<del>$1</del>");

    return html.replace(/\u0000(\d+)\u0000/g, (_, index) => `<code>${escapeHTML(codeSpans[index])}</code>`);
  }

  const fencePattern = /^\s*```(.*)$/;
  const headingPattern = /^(#{1,6})\s+(.*)$/;
  const hrPattern = /^\s*(---+|\*\*\*+|___+)\s*$/;
  const quotePattern = /^\s*>\s?(.*)$/;
  const listPattern = /^(\s*)([-*+]|\d+[.)])\s+(.*)$/;

  const splitTableRow = (line) => line.trim()
    .replace(/^\|/, "")
    .replace(/\|$/, "")
    .split("|")
    .map((cell) => cell.trim());

  const isDividerRow = (line) => {
    const cells = splitTableRow(line);
    return cells.length > 0 && cells.every((cell) => /^:?-+:?$/.test(cell));
  };

  function renderList(lines, start) {
    const first = lines[start].match(listPattern);
    if (!first) {
      return null;
    }

    const ordered = /\d/.test(first[2]);
    const sameKind = (marker) => /\d/.test(marker) === ordered;
    const baseIndent = first[1].length;
    const items = [];
    let index = start;

    while (index < lines.length) {
      const line = lines[index];

      if (line.trim() === "") {
        const next = lines[index + 1];
        const nextMatch = next !== undefined ? next.match(listPattern) : null;
        if (nextMatch && nextMatch[1].length >= baseIndent && sameKind(nextMatch[2])) {
          index++;
          continue;
        }
        break;
      }

      const match = line.match(listPattern);
      if (!match || match[1].length < baseIndent || !sameKind(match[2])) {
        break;
      }

      if (match[1].length > baseIndent) {
        const nested = renderList(lines, index);
        if (nested && items.length > 0) {
          items[items.length - 1].parts.push({ html: nested.html });
          index = nested.next;
          continue;
        }
      }

      const task = match[3].match(/^\[([ xX])\]\s+(.*)$/);
      items.push({
        checked: task ? task[1] !== " " : null,
        parts: [{ text: task ? task[2] : match[3] }]
      });
      index++;
    }

    const rendered = items.map((item) => {
      const content = item.parts.map((part) => part.html || renderInline(part.text)).join("\n");
      if (item.checked === null) {
        return `<li>${content}</li>`;
      }
      const checkbox = `<input type="checkbox" disabled${item.checked ? " checked" : ""}>`;
      return `<li class="task-list-item">${checkbox} ${content}</li>`;
    }).join("\n");

    const tag = ordered ? "ol" : "ul";
    const taskAttr = items.some((item) => item.checked !== null) ? ` class="task-list"` : "";
    return { html: `<${tag}${taskAttr}>\n${rendered}\n</${tag}>`, next: index };
  }

  function renderTable(lines, index) {
    const headerCells = splitTableRow(lines[index]);
    index += 2;

    const rows = [];
    while (index < lines.length && lines[index].trim() !== "" && lines[index].includes("|")) {
      rows.push(splitTableRow(lines[index]));
      index++;
    }

    const head = headerCells.map((cell) => `<th>${renderInline(cell)}</th>`).join("\n");
    const body = rows.map((row) =>
      `<tr>\n${row.map((cell) => `<td>${renderInline(cell)}</td>`).join("\n")}\n</tr>`
    ).join("\n");
    const bodyHTML = body ? `<tbody>\n${body}\n</tbody>` : "";

    return { html: `<table>\n<thead>\n<tr>\n${head}\n</tr>\n</thead>\n${bodyHTML}</table>`, next: index };
  }

  const opensBlock = (line) => line.trim() !== ""
    && !fencePattern.test(line)
    && !headingPattern.test(line)
    && !hrPattern.test(line)
    && !quotePattern.test(line)
    && !listPattern.test(line);

  function renderBlocks(lines) {
    const html = [];
    let index = 0;

    while (index < lines.length) {
      const line = lines[index];

      if (line.trim() === "") {
        index++;
        continue;
      }

      const fence = line.match(fencePattern);
      if (fence) {
        const body = [];
        index++;
        while (index < lines.length && !/^\s*```\s*$/.test(lines[index])) {
          body.push(lines[index]);
          index++;
        }
        index++;
        const language = fence[1].trim();
        const languageAttr = language ? ` class="language-${escapeHTML(language)}"` : "";
        html.push(`<pre><code${languageAttr}>${escapeHTML(body.join("\n"))}</code></pre>`);
        continue;
      }

      const heading = line.match(headingPattern);
      if (heading) {
        const level = heading[1].length;
        html.push(`<h${level}>${renderInline(heading[2])}</h${level}>`);
        index++;
        continue;
      }

      if (hrPattern.test(line)) {
        html.push("<hr>");
        index++;
        continue;
      }

      if (quotePattern.test(line)) {
        const quoted = [];
        while (index < lines.length) {
          const inner = lines[index].match(quotePattern);
          if (!inner) {
            break;
          }
          quoted.push(inner[1]);
          index++;
        }
        html.push(`<blockquote>\n${renderBlocks(quoted)}\n</blockquote>`);
        continue;
      }

      if (index + 1 < lines.length && lines[index].includes("|") && isDividerRow(lines[index + 1])) {
        const table = renderTable(lines, index);
        html.push(table.html);
        index = table.next;
        continue;
      }

      const list = renderList(lines, index);
      if (list) {
        html.push(list.html);
        index = list.next;
        continue;
      }

      const paragraph = [];
      while (index < lines.length && opensBlock(lines[index])) {
        paragraph.push(lines[index]);
        index++;
      }
      html.push(`<p>${paragraph.map(renderInline).join("\n")}</p>`);
    }

    return html.join("\n");
  }

  const renderMarkdown = (source) => renderBlocks(source.split("\n"));

  // Editor syntax highlighting (cosmetic, mirrors the app's highlighter)

  function renderHighlight(text) {
    let html = escapeHTML(text);

    html = html.replace(/^&gt;\s?.*$/gm, (match) => `<span class="tok-quote">${match}</span>`);
    html = html.replace(/^(\s*)([-*+]|\d+\.)\s/gm, (match, indent, marker) =>
      `${indent}<span class="tok-marker">${marker} </span>`);
    html = html.replace(/(!?)\[([^\]]*)\]\(([^)]+)\)/g, (match, bang, label) => {
      if (bang) {
        return `<span class="tok-link">${match}</span>`;
      }
      const bodyStart = match.indexOf("]") + 1;
      return `<span class="tok-link">[<span class="tok-link-label">${label}</span>]${match.slice(bodyStart)}</span>`;
    });
    html = html.replace(/~~(.+?)~~/g, (match) => `<span class="tok-strike">${match}</span>`);
    html = html.replace(/^(---+|\*\*\*+|___+)\s*$/gm, (match) => `<span class="tok-rule">${match}</span>`);

    // Keep the last empty line visible, matching the textarea's height.
    if (text.endsWith("\n")) {
      html += "\u200b";
    }
    return html;
  }

  // Demo wiring

  const demoWindow = document.querySelector(".demo-window");
  const editor = document.getElementById("demo-editor");
  if (!demoWindow || !editor) {
    return;
  }

  const highlightLayer = document.querySelector(".demo-highlight");
  const highlightCode = document.getElementById("demo-highlight-code");
  const preview = document.getElementById("demo-preview");
  const wordsStat = document.getElementById("demo-stat-words");
  const timeStat = document.getElementById("demo-stat-time");
  const cursorStat = document.getElementById("demo-stat-cursor");

  function updateStats() {
    const words = editor.value.match(/\S+/g);
    const count = words ? words.length : 0;
    wordsStat.textContent = `${count} words`;
    timeStat.textContent = count === 0 ? "< 1 min" : `${Math.ceil(count / readingSpeedWPM)} min`;
  }

  function updateCursorPosition() {
    const before = editor.value.slice(0, editor.selectionStart);
    cursorStat.textContent = `Ln ${before.split("\n").length}, Col ${editor.selectionStart - before.lastIndexOf("\n")}`;
  }

  function refresh() {
    highlightCode.innerHTML = renderHighlight(editor.value);
    preview.innerHTML = renderMarkdown(editor.value);
    updateStats();
  }

  function syncScroll() {
    highlightLayer.scrollTop = editor.scrollTop;
    highlightLayer.scrollLeft = editor.scrollLeft;
  }

  // Formatting actions

  function insertAtSelection(text) {
    editor.focus();
    if (!document.execCommand("insertText", false, text)) {
      const start = editor.selectionStart;
      editor.setRangeText(text, start, editor.selectionEnd, "end");
    }
  }

  function selectRange(start, end) {
    editor.setSelectionRange(start, end);
    updateCursorPosition();
  }

  function applyWrap(prefix, suffix) {
    const start = editor.selectionStart;
    const end = editor.selectionEnd;
    const selected = editor.value.slice(start, end) || textPlaceholder;
    insertAtSelection(prefix + selected + suffix);
  }

  function lineRange() {
    const value = editor.value;
    const start = editor.selectionStart;
    let end = editor.selectionEnd;
    if (end > start && value[end - 1] === "\n") {
      end--;
    }
    const lineStart = value.lastIndexOf("\n", start - 1) + 1;
    let lineEnd = value.indexOf("\n", end);
    if (lineEnd === -1) {
      lineEnd = value.length;
    }
    return { start: lineStart, end: lineEnd };
  }

  function replaceLines(transform) {
    const range = lineRange();
    const updated = transform(editor.value.slice(range.start, range.end).split("\n"));
    editor.setSelectionRange(range.start, range.end);
    insertAtSelection(updated.join("\n"));
  }

  function applyHeading(level) {
    const marker = "#".repeat(level) + " ";
    replaceLines((lines) => lines.map((line) => marker + line.replace(/^#{1,6}\s+/, "")));
  }

  function applyBlockquote() {
    replaceLines((lines) => {
      const allQuoted = lines.every((line) => line.startsWith(">"));
      return lines.map((line) => (allQuoted ? line.replace(/^>\s?/, "") : `> ${line}`));
    });
  }

  // Mirrors the app's list toggling: consume the existing marker, then either
  // strip it (every line already has the requested kind) or apply a new one.
  const listDecomposePattern = /^([ \t]*)(\d+\.[ \t]+|[-*+][ \t]+\[[ xX]\][ \t]+|[-*+][ \t]+)?(.*)$/;

  const listMarkers = {
    ordered: (index) => `${index}. `,
    unordered: () => "- ",
    task: () => "- [ ] "
  };

  function applyList(kind) {
    let orderedIndex = 1;
    replaceLines((lines) => {
      const decomposed = lines.map((line) => line.match(listDecomposePattern).slice(1));
      const contentLines = decomposed.filter((_, index) => !(index === lines.length - 1 && lines[index] === ""));
      const allMatch = contentLines.length > 0 && contentLines.every((parts) => {
        const marker = parts[1];
        if (!marker) {
          return false;
        }
        if (/^\d+\.\s+$/.test(marker)) {
          return kind === "ordered";
        }
        if (/\[[ xX]\]\s+$/.test(marker)) {
          return kind === "task";
        }
        return kind === "unordered";
      });

      return decomposed.map((parts, index) => {
        if (index === lines.length - 1 && lines[index] === "") {
          return lines[index];
        }
        const [indent, marker, rest] = parts;
        if (allMatch) {
          return indent + rest;
        }
        const newMarker = listMarkers[kind](orderedIndex);
        if (kind === "ordered") {
          orderedIndex++;
        }
        return indent + newMarker + rest;
      });
    });
  }

  const actionHandlers = {
    bold: () => applyWrap("**", "**"),
    italic: () => applyWrap("*", "*"),
    strikethrough: () => applyWrap("~~", "~~"),
    inlineCode: () => applyWrap("`", "`"),
    codeBlock: () => applyWrap("```\n", "\n```"),
    link: () => applyWrap("[", "](url)"),
    image: () => applyWrap("![", "](image_url)"),
    horizontalRule: () => insertAtSelection("\n---\n" + editor.value.slice(editor.selectionStart, editor.selectionEnd)),
    blockquote: applyBlockquote,
    orderedList: () => applyList("ordered"),
    unorderedList: () => applyList("unordered"),
    taskList: () => applyList("task")
  };

  demoWindow.querySelectorAll("[data-action]").forEach((button) => {
    button.addEventListener("click", () => {
      actionHandlers[button.dataset.action]();
    });
  });

  // Heading menu

  const headingButton = document.getElementById("demo-heading-button");
  const headingMenu = document.getElementById("demo-heading-menu");

  function closeHeadingMenu() {
    headingMenu.hidden = true;
    headingButton.setAttribute("aria-expanded", "false");
  }

  headingButton.addEventListener("click", () => {
    const open = headingMenu.hidden;
    headingMenu.hidden = !open;
    headingButton.setAttribute("aria-expanded", String(open));
  });

  headingMenu.querySelectorAll("[data-heading]").forEach((item) => {
    item.addEventListener("click", () => {
      applyHeading(Number(item.dataset.heading));
      closeHeadingMenu();
      headingButton.focus();
    });
  });

  document.addEventListener("pointerdown", (event) => {
    if (headingMenu.hidden) {
      return;
    }
    if (!headingMenu.contains(event.target) && !headingButton.contains(event.target)) {
      closeHeadingMenu();
    }
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && !headingMenu.hidden) {
      closeHeadingMenu();
      headingButton.focus();
    }
  });

  // View mode

  const viewButtons = [...demoWindow.querySelectorAll("[data-view]")];

  viewButtons.forEach((button) => {
    button.addEventListener("click", () => {
      demoWindow.dataset.view = button.dataset.view;
      viewButtons.forEach((other) => other.setAttribute("aria-pressed", String(other === button)));
    });
  });

  // Draggable pane divider, like the app's split view.

  const panes = demoWindow.querySelector(".demo-panes");
  const divider = document.getElementById("demo-pane-divider");
  const minPaneRatio = 0.2;
  const keyboardResizeStep = 0.02;
  const stackedLayout = window.matchMedia("(max-width: 34rem)");

  const pointerRatio = (clientX) => {
    const bounds = panes.getBoundingClientRect();
    return (clientX - bounds.left - divider.offsetWidth / 2) / (bounds.width - divider.offsetWidth);
  };

  const paneRatio = () => {
    const bounds = panes.getBoundingClientRect();
    return (panes.firstElementChild.getBoundingClientRect().width + divider.offsetWidth / 2) / bounds.width;
  };

  function setPaneRatio(ratio) {
    const clamped = Math.min(Math.max(ratio, minPaneRatio), 1 - minPaneRatio);
    panes.style.gridTemplateColumns = `${(clamped * 100).toFixed(2)}% 1px minmax(0, 1fr)`;
    divider.setAttribute("aria-valuenow", String(Math.round(clamped * 100)));
  }

  function stopPaneDrag(event) {
    divider.classList.remove("is-dragging");
    if (divider.hasPointerCapture(event.pointerId)) {
      divider.releasePointerCapture(event.pointerId);
    }
  }

  divider.addEventListener("pointerdown", (event) => {
    if (stackedLayout.matches) {
      return;
    }
    event.preventDefault();
    divider.setPointerCapture(event.pointerId);
    divider.classList.add("is-dragging");
  });

  divider.addEventListener("pointermove", (event) => {
    if (!divider.classList.contains("is-dragging")) {
      return;
    }
    setPaneRatio(pointerRatio(event.clientX));
  });

  divider.addEventListener("pointerup", stopPaneDrag);
  divider.addEventListener("pointercancel", stopPaneDrag);

  divider.addEventListener("keydown", (event) => {
    if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") {
      return;
    }
    event.preventDefault();
    const direction = event.key === "ArrowRight" ? 1 : -1;
    setPaneRatio(paneRatio() + direction * keyboardResizeStep);
  });

  // The stacked phone layout manages its own grid tracks.
  stackedLayout.addEventListener("change", () => {
    panes.style.gridTemplateColumns = "";
  });

  // Editor events

  editor.addEventListener("input", () => {
    refresh();
    updateCursorPosition();
  });
  editor.addEventListener("scroll", syncScroll);
  ["keyup", "click", "select"].forEach((eventName) => {
    editor.addEventListener(eventName, updateCursorPosition);
  });

  editor.addEventListener("keydown", (event) => {
    if (event.key === "Tab" && !event.isComposing) {
      event.preventDefault();
      insertAtSelection("\t");
      return;
    }

    // App shortcuts: ⌘B bold, ⌘I italic, ⌘K link, ⇧⌘K inline code.
    if (!event.metaKey && !event.ctrlKey) {
      return;
    }
    const shortcutActions = { b: "bold", i: "italic", k: event.shiftKey ? "inlineCode" : "link" };
    const action = shortcutActions[event.key.toLowerCase()];
    if (!action) {
      return;
    }
    event.preventDefault();
    actionHandlers[action]();
  });

  editor.value = sampleDocument;
  editor.setSelectionRange(0, 0);
  refresh();
  updateCursorPosition();
})();
