
//=========================================================
// Code related to fullscreen features that are loaded once at the start of app
//
const fullscreenFrames = new Array();

function addInnerHtmlEventListener(frame, trap, yieldFunc) {
    let iframeHtml = frame.contentWindow.document.documentElement;
    let checkYield = (e) => {
        if (e.target === iframeHtml || e.target.classList.contains('deadzone')) {
            yieldFunc(e);
        };
    };

    // capture the down event in bubbling phase
    iframeHtml.addEventListener('click', checkYield, false);
    // iframeHtml.addEventListener('pointerdown', checkYield, false);
    // iframeHtml.addEventListener('pointerup', checkYield, false);
    // iframeHtml.addEventListener('click', checkYield, false);
    // iframeHtml.addEventListener('mouseover', checkYield, false);
}

async function initHud() {
    // order affects event check, element 0 is checked first
    // background should be the last element
    const URLS = [
        // "http://0.0.0.0:9012",
        "http://0.0.0.0:9011",
        "http://0.0.0.0:9010",
    ];


    let eventTrap = document.getElementById("eventTrap");
    let handler = (e) => {
        // events get here after some frame has yielded (as a result of yielding)
        // or its the very-very first event ever
        eventTrap.classList.add('acceptevents');

        for (const child of fullscreenFrames) {
            child.classList.remove('acceptevents');
        }

        for (const child of fullscreenFrames) {
                let innerEl = child.contentWindow.document.elementFromPoint(e.clientX, e.clientY);
                let iframeHtml = child.contentWindow.document.documentElement;
                if (! innerEl 
                    || innerEl === iframeHtml 
                    || innerEl.classList.contains('deadzone')
                ) {
                    // if this child does not have any active
                    child.classList.remove('acceptevents');
                    continue;
                }

                eventTrap.classList.remove('acceptevents');
                child.classList.add('acceptevents');

                // so we do not block the thread
                let repeat = new MouseEvent(e.type, e);
                innerEl.dispatchEvent(repeat);

                break;
        };
    };

    // Object.keys(eventTrap).forEach(key => {
    //     if (/^onpointer/.test(key)) {
    //         eventTrap.addEventListener(key.slice(2), handler, true);
    //     }
    // });

    eventTrap.addEventListener('click', handler, false);

    // eventTrap.addEventListener('pointerup', handler, true);

    for (const url of URLS) {
        try {
            let feature_json = await getFeatureSrc(url);
            // dublicate requests is a known bug: https://bugzilla.mozilla.org/show_bug.cgi?id=1464344
            let iframe = document.createElement("iframe");
            iframe.classList.add("fullscreen");
            // let srcUrl = new URL()
            // iframe.src = btoa(
            iframe.src = feature_json["src"];
            // iframe.srcdoc = feature_json["text"];
            iframe.onload = () => {
                addInnerHtmlEventListener(iframe, eventTrap, handler);
            };
            fullscreenFrames.push(iframe);
        } catch (error) {
            console.log("HTTP error:" + error.message);
        };
    }

    // background element must be the last to check when assigning event handlers
    // background element must also be the first child of container (to put it in the bottom of hierarchy)
    // so iterate in reverse
    let container = document.getElementById("featuresContainer");
    for (let i = fullscreenFrames.length - 1; i >= 0; i--) {
        container.appendChild(fullscreenFrames[i]);
    }
}


//=============================================================
// Code related to small features that are loaded on user request
//
// const FEATURES = new Map();


async function getFeatureSrc(feature_url) {
    let backend = new URL("/api/getfeature", window.location);
    backend.searchParams.set('feature_url', new URL(feature_url));

    let response = await fetch(backend);
    if (!response.ok) {
        throw new Error("HTTP error, status = " + response.status);
    }
    let feature_json = await response.json();
    return feature_json;
}

// function mapBroadcast(event, map) {
//     map.forEach((featureExtraInfo, featureIFrameElem, m) => {
//         let iframeWindow = (featureIFrameElem.contentWindow || featureIFrameElem.contentDocument);
//         if (iframeWindow !== event.source) {
//             iframeWindow.postMessage(event.data, window.location.origin);
//         };
//     });
// }

function arrayBroadcast(event, array) {
    array.forEach((featureIFrameElem, index, arr) => {
        let iframeWindow = (featureIFrameElem.contentWindow || featureIFrameElem.contentDocument);
        if (iframeWindow && iframeWindow !== event.source) {
            iframeWindow.postMessage(event.data, window.location.origin);
        };
    });
}

async function onMessage(event) {
    if (event.origin !== window.top.location.origin) {
        // accept only messages for your domain
        return;
    }

    console.log("hud received: ");
    console.log(event.data);

    if (! ("info" in event.data)) {
        console.log("No 'info' field in message, skipping");
        return;
    }

    if (event.data["info"].includes("new feature")) {
        try {
            let featureJson = await getFeatureSrc(event.data["url"]);
            // dublicate requests is a known bug: https://bugzilla.mozilla.org/show_bug.cgi?id=1464344
            // let iframe = document.createElement("iframe");
            // iframe.srcdoc = featureJson["text"];
            // let featureExtraInfo = {};
            // FEATURES.set(iframe, featureExtraInfo);

            // let msg = {
            //     "info": "created feature",
            //     "feature": iframe.outerHTML,
            // };
            // let fakeEvent = {
            //     "source": "*",
            //     "data": msg,
            // }
            // // make sure every fullscreen feature knows that a new on-demand feature was added
            // arrayBroadcast(fakeEvent, fullscreenFrames);
            let msg = {
                "info": "created feature",
                "srcdoc": featureJson["text"],
                "src": featureJson["src"],
            };
            let fakeEvent = {
                "source": "xxx",
                "data": msg,
            }
            // make sure every fullscreen feature knows that a new on-demand feature was added
            arrayBroadcast(fakeEvent, fullscreenFrames);
        } catch (error) {
            console.log("HTTP error:" + error.message);
        };

//     } else if (event.data["info"].includes("small broadcast")) {
//         mapBroadcast(event, FEATURES);
// 
    } else if (event.data["info"].includes("broadcast")) {
        arrayBroadcast(event, fullscreenFrames);

    } else {
        console.log("Can not understand message info:" + event.data["info"]);
        return;
    }
}


// see: https://developer.mozilla.org/en-US/docs/Web/API/Window/postMessage
window.addEventListener("message", onMessage);



