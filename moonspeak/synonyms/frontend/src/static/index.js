import {registerRawSvgElement} from "./custom_elements.js";
import Elm from "./elmapp.js";
import {moonspeakInstallOnMessageHandler, moonspeakPostMessage} from "./moonspeak.js";

registerRawSvgElement();

const app = window.Elm.Main.init({
    node: document.getElementById("elmapp")
});

app.ports.sendMessage.subscribe(function(message) {
    moonspeakPostMessage(message);
});


function onMessage(event) {
    app.ports.messageReceiver.send(event.data);
}

moonspeakInstallOnMessageHandler(onMessage);
