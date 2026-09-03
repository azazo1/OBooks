(() => {
    const post = (body) => window.webkit?.messageHandlers?.reader?.postMessage(body);
    const root = () => document.documentElement;
    const scrollElement = () => document.scrollingElement || root();
    const report = () => {
        const flow = root().dataset.flow || "paginated";
        const element = scrollElement();
        const max = flow === "paginated"
            ? Math.max(0, element.scrollWidth - window.innerWidth)
            : Math.max(0, element.scrollHeight - window.innerHeight);
        const current = flow === "paginated" ? window.scrollX : window.scrollY;
        post({ type: "progress", fraction: max > 0 ? current / max : 0 });
    };
    const page = (direction) => {
        const flow = root().dataset.flow || "paginated";
        const element = scrollElement();
        const amount = Math.max(320, (flow === "paginated" ? window.innerWidth : window.innerHeight) * 0.86);
        if (flow === "paginated") {
            const current = window.scrollX;
            const max = Math.max(0, element.scrollWidth - window.innerWidth);
            if ((direction > 0 && current >= max - 2) || (direction < 0 && current <= 2)) {
                post({ type: "boundary", direction });
                return;
            }
            window.scrollTo({ left: Math.min(max, Math.max(0, current + direction * amount)), behavior: "smooth" });
        } else {
            const current = window.scrollY;
            const max = Math.max(0, element.scrollHeight - window.innerHeight);
            if ((direction > 0 && current >= max - 2) || (direction < 0 && current <= 2)) {
                post({ type: "boundary", direction });
                return;
            }
            window.scrollTo({ top: Math.min(max, Math.max(0, current + direction * amount)), behavior: "smooth" });
        }
    };
    const clearHighlight = () => document.querySelectorAll("[data-obooks-speech-highlight]").forEach((node) => {
        const parent = node.parentNode;
        if (!parent) return;
        while (node.firstChild) parent.insertBefore(node.firstChild, node);
        parent.removeChild(node);
        parent.normalize();
    });
    const readableText = () => {
        const clone = document.body.cloneNode(true);
        clone.querySelectorAll("script,style,[data-obooks-highlight],[data-obooks-speech-highlight]").forEach((node) => node.remove());
        return (clone.innerText || clone.textContent || "").trim();
    };
    const highlight = (start, length) => {
        clearHighlight();
        if (!Number.isFinite(start) || !Number.isFinite(length) || length <= 0) return;
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        let node;
        let offset = 0;
        let startNode = null;
        let endNode = null;
        let startOffset = 0;
        let endOffset = 0;
        while ((node = walker.nextNode())) {
            const text = node.nodeValue || "";
            const next = offset + text.length;
            if (!startNode && start >= offset && start <= next) {
                startNode = node;
                startOffset = start - offset;
            }
            if (start + length >= offset && start + length <= next) {
                endNode = node;
                endOffset = start + length - offset;
                break;
            }
            offset = next;
        }
        if (!startNode || !endNode) return;
        const range = document.createRange();
        range.setStart(startNode, Math.max(0, startOffset));
        range.setEnd(endNode, Math.max(0, endOffset));
        const mark = document.createElement("span");
        mark.dataset.obooksHighlight = "true";
        mark.className = "obooks-speech-highlight";
         delete mark.dataset.obooksHighlight;
         mark.dataset.obooksSpeechHighlight = "true";
        try {
            mark.appendChild(range.extractContents());
            range.insertNode(mark);
            mark.scrollIntoView({ block: "center", inline: "center", behavior: "smooth" });
        } catch (_) {
            clearHighlight();
        }
    };
    let selectionText = () => window.getSelection()?.toString().trim() || "";
    const removeMenu = () => document.querySelector(".obooks-context-menu")?.remove();
    const rangeHighlight = () => {
        const selection = window.getSelection();
        if (!selection || selection.rangeCount === 0 || selection.isCollapsed) return;
        const text = selectionText();
        const range = selection.getRangeAt(0);
        const mark = document.createElement("mark");
        mark.className = "obooks-user-highlight";
        mark.dataset.obooksHighlight = "true";
        try {
            mark.appendChild(range.extractContents());
            range.insertNode(mark);
            post({ type: "annotation", kind: "highlight", text });
            selection.removeAllRanges();
        } catch (_) {}
        removeMenu();
    };
    const showMenu = (event) => {
        removeMenu();
        const text = selectionText();
        if (!text) return;
        event.preventDefault();
        const menu = document.createElement("div");
        menu.className = "obooks-context-menu";
        menu.innerHTML = `
            <button data-action="highlight"><span>●</span> 高亮</button>
            <button data-action="note"><span>✎</span> 添加笔记</button>
            <button data-action="speak"><span>◖</span> 从此处开始朗读</button>
        `;
        menu.style.left = `${Math.min(event.clientX, window.innerWidth - 190)}px`;
        menu.style.top = `${Math.min(event.clientY, window.innerHeight - 138)}px`;
        menu.addEventListener("click", (clickEvent) => {
            const action = clickEvent.target.closest("button")?.dataset.action;
            if (action === "highlight") rangeHighlight();
            if (action === "note") {
                post({ type: "noteRequest", text });
                removeMenu();
            }
            if (action === "speak") {
                post({ type: "annotation", kind: "speech", text });
                removeMenu();
            }
        });
        document.body.appendChild(menu);
    };
    document.addEventListener("contextmenu", showMenu);
    document.addEventListener("click", removeMenu);

    window.obooksReader = {
        setSettings(settings) {
            root().dataset.flow = settings.flow;
            root().dataset.theme = settings.theme;
            root().style.setProperty("--obooks-font-size", settings.fontSize + "px");
            root().style.setProperty("--obooks-line-height", settings.lineHeight);
            root().style.setProperty("--obooks-margin", settings.margin + "px");
            report();
        },
        nextPage: () => page(1),
        previousPage: () => page(-1),
        readableText,
        highlight,
        clearHighlight
    };
    window.addEventListener("scroll", report, { passive: true });
    window.addEventListener("resize", report, { passive: true });
    post({ type: "ready" });
})();
