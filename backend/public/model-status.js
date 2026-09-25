(() => {
    const modelElements = document.querySelectorAll("[data-runtime-model]");
    const statusElements = document.querySelectorAll("[data-runtime-status]");

    if (!modelElements.length) return;

    const setStatus = (value) => {
        statusElements.forEach((element) => {
            element.textContent = value;
        });
    };

    fetch("/api/public-config", { cache: "no-store" })
        .then((response) => {
            if (!response.ok) throw new Error("Configuration request failed");
            return response.json();
        })
        .then((config) => {
            modelElements.forEach((element) => {
                const value = config[element.dataset.runtimeModel];
                element.textContent = typeof value === "string" && value.trim()
                    ? value
                    : "Not configured";
            });
            setStatus("LIVE DEPLOYMENT CONFIG");
        })
        .catch(() => {
            modelElements.forEach((element) => {
                element.textContent = "Unable to load";
            });
            setStatus("CONFIG UNAVAILABLE");
        });
})();