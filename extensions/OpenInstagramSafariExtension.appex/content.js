// Redirect instagram.com web links into the native app.
// Shipped inside RyukGram as a Safari web extension.

(function () {
    if (window.top !== window.self) return;
    if (sessionStorage.getItem("__sciOpenedApp")) return;

    function urlFromLocation() {
        const path = window.location.pathname.split("/").filter(Boolean);
        if (path.length === 0) return null;

        if (path[0] === "p" || path[0] === "reel") {
            const meta = document.querySelector("meta[property='al:ios:url']");
            if (meta && meta.getAttribute("content")) return meta.getAttribute("content");
            return path[1] ? `instagram://media?id=${path[1]}` : null;
        }

        if (path[0] === "stories" && path[1]) {
            return `instagram://story?username=${path[1]}`;
        }

        if (path[0] === "explore" && path[1] === "tags" && path[2]) {
            return `instagram://tag?name=${path[2]}`;
        }

        if (path.length === 1) {
            return `instagram://user?username=${path[0]}`;
        }

        return null;
    }

    function openInApp() {
        const target = urlFromLocation();
        if (!target) return;
        sessionStorage.setItem("__sciOpenedApp", "1");
        window.location.href = target;
    }

    openInApp();
})();
