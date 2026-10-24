//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic

// Adjust this to make the app smaller or larger
//@ pragma Env QT_SCALE_FACTOR=1

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Steam sign-in for steamcmd, used by the Wallpaper Engine Workshop tab of the
 * wallpaper selector. Handles Steam Guard email codes, authenticator codes and
 * Steam Mobile app confirmations through scripts/wallpaperEngine/login.py.
 */
ApplicationWindow {
    id: root
    property string loginScriptPath: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/wallpaperEngine/login.py`
    property real contentPadding: 8

    property string stage: "form" // "form", "busy", "code", "done"
    property string busyStatus: ""
    property string codeKind: "" // "email", "mobile"
    property bool codeInvalid: false
    property string errorText: ""

    visible: true
    onClosing: {
        if (loginProc.running) loginProc.write("CANCEL\n");
        Qt.quit();
    }
    title: Translation.tr("Steam sign-in")

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme();
        userField.text = Config.options.wallpaperSelector.wallpaperEngine.steamUser;
        (userField.text.length > 0 ? passwordField : userField).forceActiveFocus();
    }

    minimumWidth: 420
    minimumHeight: 500
    maximumWidth: 420
    maximumHeight: 500
    width: 420
    height: 500
    color: Appearance.m3colors.m3background

    function signIn() {
        const user = userField.text.trim();
        if (user.length === 0 || passwordField.text.length === 0) return;
        root.errorText = "";
        root.codeInvalid = false;
        root.busyStatus = Translation.tr("Connecting to Steam...");
        root.stage = "busy";
        loginProc.user = user;
        loginProc.command = ["python3", root.loginScriptPath, "--user", user, ...(rememberSwitch.checked ? ["--remember"] : [])];
        loginProc.running = true;
    }

    function submitCode() {
        const code = codeField.text.trim();
        if (code.length === 0) return;
        loginProc.write(`CODE ${code}\n`);
        codeField.text = "";
    }

    function cancel() {
        if (loginProc.running) loginProc.write("CANCEL\n");
        root.stage = "form";
    }

    Process {
        id: loginProc
        property string user
        property bool finished: false
        stdinEnabled: true
        onStarted: {
            loginProc.finished = false;
            loginProc.write(passwordField.text + "\n");
            passwordField.text = "";
        }
        stdout: SplitParser {
            onRead: line => {
                const [event, ...rest] = line.split(" ");
                if (event === "STATUS") {
                    root.busyStatus = rest[0] === "checking" ? Translation.tr("Checking the code...") : Translation.tr("Connecting to Steam...");
                    root.stage = "busy";
                } else if (event === "NEED_CODE") {
                    root.codeKind = rest[0];
                    root.stage = "code";
                    codeField.forceActiveFocus();
                } else if (event === "CODE_INVALID") {
                    root.codeInvalid = true;
                } else if (event === "CONFIRM") {
                    root.busyStatus = Translation.tr("Confirm the sign-in in the Steam Mobile app");
                    root.stage = "busy";
                } else if (event === "DONE") {
                    loginProc.finished = true;
                    Config.options.wallpaperSelector.wallpaperEngine.steamUser = loginProc.user;
                    // Let the shell retry the download that needed this login
                    Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "wallpaperEngine", "loginFinished"]);
                    root.stage = "done";
                } else if (event === "ERROR") {
                    loginProc.finished = true;
                    root.errorText = rest.slice(1).join(" ");
                    root.stage = "form";
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (loginProc.finished || root.stage === "form") return;
            root.errorText = Translation.tr("steamcmd stopped unexpectedly (exit code %1)").arg(exitCode);
            root.stage = "form";
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: root.contentPadding
        }

        Item {
            // Titlebar
            visible: Config.options?.windows.showTitlebar
            Layout.fillWidth: true
            implicitHeight: Math.max(titleText.implicitHeight, windowControlsRow.implicitHeight)
            StyledText {
                id: titleText
                anchors {
                    left: Config.options.windows.centerTitle ? undefined : parent.left
                    horizontalCenter: Config.options.windows.centerTitle ? parent.horizontalCenter : undefined
                    verticalCenter: parent.verticalCenter
                    leftMargin: 12
                }
                color: Appearance.colors.colOnLayer0
                text: Translation.tr("Steam sign-in")
                font {
                    family: Appearance.font.family.title
                    pixelSize: Appearance.font.pixelSize.title
                    variableAxes: Appearance.font.variableAxes.title
                }
            }
            RowLayout { // Window controls row
                id: windowControlsRow
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                RippleButton {
                    buttonRadius: Appearance.rounding.full
                    implicitWidth: 35
                    implicitHeight: 35
                    onClicked: root.close()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "close"
                        iconSize: 20
                    }
                }
            }
        }

        Rectangle {
            // Content container
            color: Appearance.m3colors.m3surfaceContainerLow
            radius: Appearance.rounding.windowRounding - root.contentPadding
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors {
                    fill: parent
                    margins: 20
                }
                spacing: 12

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    iconSize: 48
                    color: root.stage === "done" ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                    text: root.stage === "done" ? "check_circle" : root.stage === "code" ? "password" : "account_circle"
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                    text: {
                        switch (root.stage) {
                        case "code": return root.codeKind === "email"
                            ? Translation.tr("Steam sent a Steam Guard code to your email")
                            : Translation.tr("Enter the code from the Steam Guard Mobile Authenticator");
                        case "done": return Translation.tr("Signed in as %1. Workshop wallpapers can be downloaded now.").arg(loginProc.user);
                        default: return Translation.tr("steamcmd downloads Wallpaper Engine wallpapers with this account, so it must own Wallpaper Engine");
                        }
                    }
                }

                // Sign-in form
                ColumnLayout {
                    visible: root.stage === "form"
                    Layout.fillWidth: true
                    spacing: 8

                    MaterialTextField {
                        id: userField
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("Account name")
                        wrapMode: TextEdit.NoWrap
                        onAccepted: passwordField.forceActiveFocus()
                    }
                    MaterialTextField {
                        id: passwordField
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("Password")
                        wrapMode: TextEdit.NoWrap
                        echoMode: TextInput.Password
                        onAccepted: root.signIn()
                    }
                    ConfigSwitch {
                        id: rememberSwitch
                        Layout.fillWidth: true
                        buttonIcon: "key"
                        text: Translation.tr("Save password to the keyring")
                        checked: true
                        StyledToolTip {
                            text: Translation.tr("Lets downloads sign in again if steamcmd forgets the session")
                        }
                    }
                    StyledText {
                        visible: root.errorText.length > 0
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: Appearance.colors.colError
                        text: root.errorText
                    }
                }

                // Steam Guard code
                ColumnLayout {
                    visible: root.stage === "code"
                    Layout.fillWidth: true
                    spacing: 8

                    MaterialTextField {
                        id: codeField
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("Steam Guard code")
                        wrapMode: TextEdit.NoWrap
                        font.capitalization: Font.AllUppercase
                        onTextChanged: if (text.length > 0) root.codeInvalid = false
                        onAccepted: root.submitCode()
                    }
                    StyledText {
                        visible: root.codeInvalid
                        color: Appearance.colors.colError
                        text: Translation.tr("Wrong code, try again")
                    }
                }

                // Waiting
                ColumnLayout {
                    visible: root.stage === "busy"
                    Layout.fillWidth: true
                    spacing: 12

                    MaterialLoadingIndicator {
                        Layout.alignment: Qt.AlignHCenter
                        loading: root.stage === "busy"
                    }
                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: root.busyStatus
                    }
                }

                Item {
                    Layout.fillHeight: true
                }

                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: 8

                    DialogButton {
                        visible: root.stage === "busy" || root.stage === "code"
                        buttonText: Translation.tr("Cancel")
                        onClicked: root.cancel()
                    }
                    DialogButton {
                        visible: root.stage === "form"
                        enabled: userField.text.trim().length > 0 && passwordField.text.length > 0
                        buttonText: Translation.tr("Sign in")
                        onClicked: root.signIn()
                    }
                    DialogButton {
                        visible: root.stage === "code"
                        enabled: codeField.text.trim().length > 0
                        buttonText: Translation.tr("Submit")
                        onClicked: root.submitCode()
                    }
                    DialogButton {
                        visible: root.stage === "done"
                        buttonText: Translation.tr("Close")
                        onClicked: root.close()
                    }
                }
            }
        }
    }
}
