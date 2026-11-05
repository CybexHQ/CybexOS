pragma ComponentBehavior: Bound
import QtQuick
import "../Common"
import "../Common/SettingsHelpers.js" as SettingsHelpers
import "../Popovers"

// Assistant → Dictation (docs/dictation.md): the speech model and languages,
// the words dictation should know or write differently, tidy-up, and the
// history. The values are the menubar indicator's module options, as they
// have always been; the page is where they are explained.
SettingsPage {
    id: page

    readonly property var opts: Settings.modOpts.indicators
    readonly property var defaults: Settings.defaults.modOpts.indicators

    function dirty(key) {
        return JSON.stringify(opts[key]) !== JSON.stringify(defaults[key]);
    }

    function setOpt(key, value) {
        Settings.setModuleOption("indicators", key, value);
    }

    function resetOpt(key) {
        Settings.setModuleOption("indicators", key, defaults[key]);
    }

    readonly property var languageChoices: SettingsHelpers.DICTATION_LANGUAGES.map(
        code => ({value: code, label: I18n.localeName(code)}))
    readonly property bool downloading: Dictation.download === "running"

    function megabytes(bytes) {
        return Math.round(bytes / 1048576) + " MB";
    }

    function downloadProblem() {
        return Dictation.downloadError === "space"
            ? I18n.tr("There is not enough free disk space for the speech model.")
            : Dictation.downloadError === "checksum"
                ? I18n.tr("The downloaded model did not match. Nothing was installed.")
                : I18n.tr("The download did not finish. Check your connection and try again.");
    }

    readonly property string languageNames: {
        const names = [I18n.localeName(opts.dictationPrimaryLanguage)];
        if (opts.dictationSecondaryLanguage !== "off" && opts.dictationSecondaryLanguage !== opts.dictationPrimaryLanguage)
            names.push(I18n.localeName(opts.dictationSecondaryLanguage));
        return names.join(I18n.tr(" and "));
    }

    readonly property var models: [
        {
            value: "base", name: I18n.tr("Standard"), detail: I18n.tr("Whisper base · 99 languages"),
            installed: true, key: "", size: 0,
            hint: I18n.tr("Built in and fast. Good for short messages in a quiet room.")
        },
        {
            value: "large-v3-turbo", name: I18n.tr("Accurate"),
            detail: I18n.format(I18n.tr("Whisper turbo · %1 · 99 languages"), [megabytes(Dictation.enhancedSize)]),
            installed: Dictation.enhancedInstalled, key: "enhanced", size: Dictation.enhancedSize,
            hint: I18n.tr("Much more accurate, especially for names and less common languages. Slower on computers without a graphics card.")
        },
        {
            value: "parakeet", name: I18n.tr("Fast & accurate"),
            detail: I18n.format(I18n.tr("Parakeet · %1 · 25 European languages"), [megabytes(Dictation.parakeetSize)]),
            installed: Dictation.parakeetInstalled, key: "parakeet", size: Dictation.parakeetSize,
            fits: Dictation.parakeetFits,
            hint: Dictation.parakeetFits
                ? I18n.format(I18n.tr("As accurate as Accurate for %1, and several times faster. It recognises the language by itself."), [languageNames])
                : I18n.format(I18n.tr("Not available for %1: it knows 25 European languages."), [languageNames])
        }
    ]
    readonly property var chosenModel: models.find(model => model.value === opts.dictationModel) || models[0]

    readonly property string agent: opts.dictationPolishAgent
    readonly property var agentStatus: Assistant.agents[agent] || ({})
    readonly property string agentLabel: agent === "codex" ? "Codex" : "Claude Code"

    onVisibleChanged: {
        if (visible) {
            Dictation.refreshStatus();
            Dictation.refreshHistory();
        }
    }
    Component.onCompleted: {
        Dictation.refreshStatus();
        Dictation.refreshHistory();
    }

    // ---- a choice drawn as a card: a model or a tidy-up level -------------------------------
    component ChoiceCard: Rectangle {
        id: choice
        property string title: ""
        property string detail: ""
        property string badge: ""
        property string status: ""
        property color statusColor: Theme.textLow
        property bool selected: false
        property real progress: -1
        signal chosen()

        height: cardColumn.implicitHeight + Theme.scaled(20)
        radius: Theme.chipRadius
        // A chosen card is a selected tile (docs/shell-states.md): the accent
        // tint and a 2 px mark border, apart from the neutral hover.
        color: selected ? Theme.selectedFill : cardMouse.containsMouse && enabled ? Theme.hoverFillStrong : Theme.hoverFill
        border.width: selected ? Theme.selectedBorderWidth : 1
        border.color: selected ? Theme.selectedMark : Theme.stroke
        activeFocusOnTab: enabled
        Accessible.role: Accessible.RadioButton
        Accessible.name: title + ". " + detail + (status !== "" ? ". " + status : "")
        Accessible.checked: selected
        Keys.onSpacePressed: choice.chosen()
        Keys.onReturnPressed: choice.chosen()

        // Keyboard focus stands 2 px clear of the card, never on its border.
        Rectangle {
            anchors.fill: parent
            anchors.margins: -(Theme.focusRingWidth + 2)
            radius: parent.radius + Theme.focusRingWidth + 2
            color: "transparent"
            visible: border.width > 0
            border.width: Theme.focusWidth(choice.activeFocus)
            border.color: Theme.focusRing
        }

        Column {
            id: cardColumn
            x: Theme.scaled(10)
            y: Theme.scaled(10)
            width: parent.width - Theme.scaled(20)
            spacing: Theme.scaled(4)

            // A card that cannot be chosen fades its name and description;
            // the status line under them says why, at full contrast.
            Row {
                opacity: choice.enabled ? 1 : 0.55
                spacing: Theme.scaled(6)
                Text {
                    text: choice.title
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.control
                    font.weight: Theme.weightSemibold
                    color: Theme.textHi
                }
                Rectangle {
                    visible: choice.badge !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    width: badgeText.implicitWidth + Theme.scaled(10)
                    height: badgeText.implicitHeight + Theme.scaled(2)
                    radius: height / 2
                    color: Theme.accent
                    Text {
                        id: badgeText
                        anchors.centerIn: parent
                        text: choice.badge
                        font.family: Theme.fontMenu
                        font.pixelSize: Theme.typography.metadata
                        font.weight: Theme.weightSemibold
                        color: Theme.textOnAccent
                    }
                }
            }
            Text {
                width: parent.width
                opacity: choice.enabled ? 1 : 0.55
                wrapMode: Text.WordWrap
                text: choice.detail
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.metadata
                color: Theme.textLow
            }
            Text {
                visible: choice.status !== ""
                width: parent.width
                wrapMode: Text.WordWrap
                text: choice.status
                font.family: Theme.fontMenu
                font.pixelSize: Theme.typography.metadata
                color: choice.statusColor
            }
            BlockMeter {
                visible: choice.progress >= 0
                width: parent.width
                height: Theme.scaled(6)
                value: Math.max(0, choice.progress) / 100
                accessibleName: I18n.tr("Download progress")
            }
        }

        MouseArea {
            id: cardMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: choice.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: choice.chosen()
        }
    }

    component WordList: Column {
        id: words
        spacing: Theme.scaled(10)
        readonly property var terms: SettingsHelpers.dictationTerms(page.opts.dictationVocabulary)
        readonly property var rules: page.opts.dictationCorrections || []

        // Names and terms
        Text {
            x: Theme.settingsMarkInset
            text: I18n.tr("Names and terms")
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.control
            color: page.dirty("dictationVocabulary") ? Theme.textHi : Theme.textMid
        }

        Flow {
            x: Theme.settingsMarkInset
            width: parent.width - Theme.settingsMarkInset
            spacing: Theme.scaled(6)

            Repeater {
                model: words.terms

                Rectangle {
                    id: termChip
                    required property string modelData
                    width: termRow.implicitWidth + Theme.scaled(16)
                    height: Theme.chipHeight
                    radius: height / 2
                    color: Theme.hoverFill
                    border.width: 1
                    border.color: Theme.stroke

                    Row {
                        id: termRow
                        x: Theme.scaled(10)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.scaled(2)

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: termChip.modelData
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.typography.control
                            color: Theme.textHi
                        }
                        SettingsAction {
                            anchors.verticalCenter: parent.verticalCenter
                            compact: true
                            glyph: "close"
                            text: I18n.format(I18n.tr("Remove %1"), [termChip.modelData])
                            onTriggered: Dictation.removeTerm(termChip.modelData)
                        }
                    }
                }
            }

            SettingsField {
                id: termField
                width: Theme.scaled(180, Theme.typeScale)
                height: Theme.chipHeight
                placeholderText: I18n.tr("Add a name or term")
                onAccepted: {
                    if (text.trim() !== "") {
                        Dictation.addTerm(text.trim());
                        text = "";
                    }
                }
            }
        }

        SettingsHint {
            width: parent.width
            text: page.opts.dictationModel === "parakeet"
                ? I18n.tr("Standard and Accurate expect these words. Fast & accurate cannot be told them: add corrections for the words it gets wrong.")
                : I18n.tr("The speech model expects these words, so it hears them more often. Press Enter to add one.")
        }

        // Corrections
        Text {
            x: Theme.settingsMarkInset
            text: I18n.tr("Corrections")
            font.family: Theme.fontMenu
            font.pixelSize: Theme.typography.control
            color: page.dirty("dictationCorrections") ? Theme.textHi : Theme.textMid
        }

        SettingsHint {
            width: parent.width
            text: I18n.tr("When dictation keeps writing the wrong thing, write what you meant instead. Whole words, in any case.")
        }

        Repeater {
            model: words.rules

            Item {
                id: ruleRow
                required property var modelData
                x: Theme.settingsMarkInset
                width: words.width - Theme.settingsMarkInset
                height: Theme.chipHeight

                Text {
                    id: heardText
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: (parent.width - Theme.iconSmall - removeRule.width - Theme.controlSpacing * 3) / 2
                    elide: Text.ElideRight
                    text: ruleRow.modelData.heard
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.control
                    color: Theme.textMid
                }
                Sym {
                    id: arrow
                    anchors.left: heardText.right
                    anchors.leftMargin: Theme.controlSpacing
                    anchors.verticalCenter: parent.verticalCenter
                    name: "arrow-right"
                    size: Theme.iconSmall
                    color: Theme.textLow
                }
                Text {
                    anchors.left: arrow.right
                    anchors.leftMargin: Theme.controlSpacing
                    anchors.right: removeRule.left
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: ruleRow.modelData.write
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.control
                    color: Theme.textHi
                }
                SettingsAction {
                    id: removeRule
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    compact: true
                    glyph: "close"
                    text: I18n.format(I18n.tr("Remove the correction for %1"), [ruleRow.modelData.heard])
                    onTriggered: Dictation.removeCorrection(ruleRow.modelData.heard)
                }
            }
        }

        Row {
            x: Theme.settingsMarkInset
            width: parent.width - Theme.settingsMarkInset
            spacing: Theme.controlSpacing
            readonly property real fieldWidth: (width - Theme.iconSmall - addRule.width - spacing * 3) / 2

            SettingsField {
                id: heardField
                width: parent.fieldWidth
                placeholderText: I18n.tr("When I say…")
                onAccepted: writeField.forceActiveFocus()
            }
            Sym {
                anchors.verticalCenter: parent.verticalCenter
                name: "arrow-right"
                size: Theme.iconSmall
                color: Theme.textLow
            }
            SettingsField {
                id: writeField
                width: parent.fieldWidth
                placeholderText: I18n.tr("Write…")
                onAccepted: addRule.add()
            }
            SettingsAction {
                id: addRule
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("Add")
                glyph: "add"
                enabled: heardField.text.trim() !== "" && writeField.text.trim() !== ""
                function add() {
                    if (!enabled)
                        return;
                    Dictation.addCorrection(heardField.text, writeField.text);
                    heardField.text = "";
                    writeField.text = "";
                    heardField.forceActiveFocus();
                }
                onTriggered: add()
            }
        }

        // A correction learned from the history
        Rectangle {
            id: suggestionBox
            readonly property var suggestion: Dictation.openSuggestions.length > 0 ? Dictation.openSuggestions[0] : null
            visible: suggestion !== null
            x: Theme.settingsMarkInset
            width: parent.width - Theme.settingsMarkInset
            height: suggestionRow.implicitHeight + Theme.scaled(16)
            radius: Theme.chipRadius
            color: Theme.chip
            border.width: 1
            border.color: Theme.stroke

            Row {
                id: suggestionRow
                x: Theme.scaled(10)
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - Theme.scaled(20)
                spacing: Theme.controlSpacing

                Sym {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "sparkles"
                    size: Theme.iconSmall
                    color: Theme.accentText
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Theme.iconSmall - acceptSuggestion.width - declineSuggestion.width - Theme.controlSpacing * 3
                    wrapMode: Text.WordWrap
                    text: suggestionBox.suggestion
                        ? I18n.format(I18n.tr("You changed “%1” to “%2” %3 times. Always write it that way?"),
                            [suggestionBox.suggestion.heard, suggestionBox.suggestion.write, suggestionBox.suggestion.count])
                        : ""
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.secondary
                    color: Theme.textHi
                }
                SettingsAction {
                    id: acceptSuggestion
                    anchors.verticalCenter: parent.verticalCenter
                    primary: true
                    text: I18n.tr("Add")
                    onTriggered: Dictation.acceptSuggestion(suggestionBox.suggestion)
                }
                SettingsAction {
                    id: declineSuggestion
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("No")
                    onTriggered: Dictation.declineSuggestion(suggestionBox.suggestion)
                }
            }
        }

        SettingsHint {
            width: parent.width
            text: I18n.tr("Correct a dictation in the history and the same fix made twice is suggested here. Other apps' text is never read.")
        }
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Theme.settingsGroupSpacing

        // ---- not on this computer ------------------------------------------------------------------
        SettingsGroup {
            visible: !Dictation.available
            width: parent.width
            title: I18n.tr("Dictation")

            SettingsHint {
                width: parent.width
                text: Dictation.cpuSupported
                    ? I18n.tr("Dictation comes with the developer tools feature, which this installation does not have.")
                    : I18n.tr("Dictation needs a processor with AVX2 (Intel from 2013, AMD from 2015 on).")
            }
        }

        // ---- speech -------------------------------------------------------------------------------
        SettingsGroup {
            visible: Dictation.available
            width: parent.width
            title: I18n.tr("Speech")

            SelectRow {
                width: parent.width
                label: I18n.tr("Language")
                model: page.languageChoices
                current: page.opts.dictationPrimaryLanguage
                dirty: page.dirty("dictationPrimaryLanguage")
                onPicked: value => page.setOpt("dictationPrimaryLanguage", value)
                onResetRequested: page.resetOpt("dictationPrimaryLanguage")
            }

            SelectRow {
                width: parent.width
                label: I18n.tr("Second language")
                model: [{value: "off", label: I18n.tr("None")}].concat(page.languageChoices
                    .filter(choice => choice.value !== page.opts.dictationPrimaryLanguage))
                current: page.opts.dictationSecondaryLanguage
                dirty: page.dirty("dictationSecondaryLanguage")
                hint: page.opts.dictationSecondaryLanguage === "off" ? ""
                    : I18n.tr("Dictation recognises which of your two languages you speak.")
                onPicked: value => page.setOpt("dictationSecondaryLanguage", value)
                onResetRequested: page.resetOpt("dictationSecondaryLanguage")
            }

            Column {
                width: parent.width
                spacing: Theme.scaled(8)

                Text {
                    x: Theme.settingsMarkInset
                    text: I18n.tr("Speech model")
                    font.family: Theme.fontMenu
                    font.pixelSize: Theme.typography.control
                    color: page.dirty("dictationModel") ? Theme.textHi : Theme.textMid
                }

                Grid {
                    id: modelGrid
                    x: Theme.settingsMarkInset
                    width: parent.width - Theme.settingsMarkInset
                    columns: width >= Theme.scaled(480) ? 3 : 1
                    spacing: Theme.scaled(8)
                    readonly property real cell: (width - spacing * (columns - 1)) / columns

                    Repeater {
                        model: page.models

                        ChoiceCard {
                            required property var modelData
                            readonly property bool loading: page.downloading && Dictation.downloadModel === modelData.key
                            width: modelGrid.cell
                            enabled: modelData.fits !== false && Dictation.statusKnown
                            title: modelData.name
                            detail: modelData.detail
                            badge: modelData.value === Dictation.recommendedModel && modelData.fits !== false
                                && Dictation.recommendedModel === "parakeet" ? I18n.tr("Best") : ""
                            selected: page.opts.dictationModel === modelData.value
                            progress: loading ? Dictation.downloadProgress : -1
                            status: loading ? I18n.format(I18n.tr("Downloading… %1%"), [Dictation.downloadProgress])
                                : modelData.fits === false ? I18n.tr("Not for these languages")
                                : modelData.installed ? (modelData.key === "" ? I18n.tr("Built in") : I18n.tr("Downloaded"))
                                : I18n.format(I18n.tr("Choose to download %1"), [page.megabytes(modelData.size)])
                            statusColor: modelData.installed && !loading ? Theme.ok : Theme.textLow
                            onChosen: Dictation.useModel(modelData.value)
                        }
                    }
                }

                SettingsHint {
                    width: parent.width
                    tone: Dictation.download === "failed" ? "error" : "info"
                    text: Dictation.download === "failed" ? page.downloadProblem() : page.chosenModel.hint
                }

                ActionRow {
                    width: parent.width
                    visible: page.downloading || Dictation.download === "failed"
                        || Dictation.enhancedInstalled || Dictation.parakeetInstalled

                    SettingsAction {
                        visible: page.downloading
                        text: I18n.tr("Cancel download")
                        glyph: "close"
                        onTriggered: Dictation.cancelDownload()
                    }
                    SettingsAction {
                        visible: Dictation.download === "failed"
                        text: I18n.tr("Try again")
                        glyph: "download"
                        onTriggered: Dictation.downloadModelNamed(Dictation.downloadModel || "enhanced")
                    }
                    SettingsAction {
                        visible: Dictation.enhancedInstalled && !(page.downloading && Dictation.downloadModel === "enhanced")
                        text: I18n.format(I18n.tr("Remove %1"), [I18n.tr("Accurate")])
                        danger: true
                        onTriggered: Dictation.removeModel("enhanced")
                    }
                    SettingsAction {
                        visible: Dictation.parakeetInstalled && !(page.downloading && Dictation.downloadModel === "parakeet")
                        text: I18n.format(I18n.tr("Remove %1"), [I18n.tr("Fast & accurate")])
                        danger: true
                        onTriggered: Dictation.removeModel("parakeet")
                    }
                }
            }

            SwitchRow {
                width: parent.width
                label: I18n.tr("Live text")
                description: I18n.tr("Show your words while you speak. Keeps the speech model loaded, which uses more memory.")
                checked: page.opts.dictationLiveText
                dirty: page.dirty("dictationLiveText")
                onToggled: value => page.setOpt("dictationLiveText", value)
                onResetRequested: page.resetOpt("dictationLiveText")
            }
        }

        // ---- words ----------------------------------------------------------------------------------
        SettingsGroup {
            visible: Dictation.available
            width: parent.width
            title: I18n.tr("Words")

            WordList {
                width: parent.width
            }
        }

        // ---- tidy-up ------------------------------------------------------------------------------
        SettingsGroup {
            visible: Dictation.available
            width: parent.width
            title: I18n.tr("Tidy up")

            Column {
                width: parent.width
                spacing: Theme.scaled(8)

                Grid {
                    id: tidyGrid
                    x: Theme.settingsMarkInset
                    width: parent.width - Theme.settingsMarkInset
                    columns: width >= Theme.scaled(420) ? 3 : 1
                    spacing: Theme.scaled(8)
                    readonly property real cell: (width - spacing * (columns - 1)) / columns

                    Repeater {
                        model: [
                            {value: "off", name: I18n.tr("Off"), detail: I18n.tr("Exactly what you said")},
                            {value: "basic", name: I18n.tr("Basic"), detail: I18n.tr("Hesitations out, capitals and full stops")},
                            {value: "polish", name: I18n.tr("Polish"), detail: I18n.tr("Clean sentences, same meaning")}
                        ]

                        ChoiceCard {
                            required property var modelData
                            width: tidyGrid.cell
                            title: modelData.name
                            detail: modelData.detail
                            selected: page.opts.dictationTidy === modelData.value
                            onChosen: page.setOpt("dictationTidy", modelData.value)
                        }
                    }
                }

                // What each level does to the same sentence.
                Rectangle {
                    x: Theme.settingsMarkInset
                    width: parent.width - Theme.settingsMarkInset
                    height: example.implicitHeight + Theme.scaled(16)
                    radius: Theme.chipRadius
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.stroke

                    Grid {
                        id: example
                        x: Theme.scaled(10)
                        y: Theme.scaled(8)
                        width: parent.width - Theme.scaled(20)
                        columns: 2
                        columnSpacing: Theme.controlSpacing
                        rowSpacing: Theme.scaled(6)

                        Text {
                            text: I18n.tr("Said")
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.typography.metadata
                            color: Theme.textLow
                        }
                        Text {
                            width: example.width - Theme.scaled(70)
                            wrapMode: Text.WordWrap
                            text: I18n.tr("Um, so can you, uh, send the cyber OS build to John tomorrow, no wait, Friday?")
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.typography.secondary
                            color: Theme.textMid
                        }
                        Text {
                            text: I18n.tr("Typed")
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.typography.metadata
                            color: Theme.textLow
                        }
                        Text {
                            width: example.width - Theme.scaled(70)
                            wrapMode: Text.WordWrap
                            text: page.opts.dictationTidy === "polish"
                                ? I18n.tr("Can you send the Cybex OS build to John on Friday?")
                                : page.opts.dictationTidy === "basic"
                                    ? I18n.tr("So can you send the Cybex OS build to John tomorrow, no wait, Friday?")
                                    : I18n.tr("Um, so can you, uh, send the Cybex OS build to John tomorrow, no wait, Friday?")
                            font.family: Theme.fontMenu
                            font.pixelSize: Theme.typography.secondary
                            color: Theme.textHi
                        }
                    }
                }

                SettingsHint {
                    width: parent.width
                    text: page.opts.dictationTidy === "polish"
                        ? I18n.format(I18n.tr("Rewrites into clean sentences and follows your own corrections (\"no wait\"). %1 does it, which takes a few seconds: only the text goes to it, never the recording. Click the pill meanwhile to type the words as said."), [page.agentLabel])
                        : page.opts.dictationTidy === "basic"
                            ? I18n.tr("Takes out um and uh and adds capitals and a full stop, on this computer, instantly. Corrections (above) apply too.")
                            : I18n.tr("Types what was heard. Corrections (above) still apply.")
                }
            }

            SelectRow {
                visible: page.opts.dictationTidy === "polish"
                width: parent.width
                label: I18n.tr("Polish with")
                model: [
                    {value: "claude", label: "Claude Code"},
                    {value: "codex", label: "Codex"}
                ]
                current: page.opts.dictationPolishAgent
                dirty: page.dirty("dictationPolishAgent")
                hintTone: page.agentStatus.available && page.agentStatus.auth === "ready" ? "info" : "warning"
                hint: !page.agentStatus.available ? I18n.format(I18n.tr("%1 is not installed. Until it is, dictations get basic tidy-up."), [page.agentLabel])
                    : page.agentStatus.auth !== "ready" ? I18n.format(I18n.tr("%1 is not signed in (Assistant → Wiz). Until it is, dictations get basic tidy-up."), [page.agentLabel])
                    : I18n.tr("Uses your own account, with a small, fast model and no tools.")
                onPicked: value => page.setOpt("dictationPolishAgent", value)
                onResetRequested: page.resetOpt("dictationPolishAgent")
            }

            SwitchRow {
                width: parent.width
                label: I18n.tr("Leave terminals and code editors alone")
                description: I18n.tr("Types exactly what you said in Ghostty, VS Code, Zed and similar apps.")
                checked: !page.opts.dictationTidyCode
                dirty: page.dirty("dictationTidyCode")
                onToggled: value => page.setOpt("dictationTidyCode", !value)
                onResetRequested: page.resetOpt("dictationTidyCode")
            }
        }

        // ---- history ------------------------------------------------------------------------------
        SettingsGroup {
            visible: Dictation.available
            width: parent.width
            title: I18n.tr("History")

            SelectRow {
                width: parent.width
                label: I18n.tr("Keep dictations")
                model: [
                    {value: "month", label: I18n.tr("30 days")},
                    {value: "forever", label: I18n.tr("Forever")},
                    {value: "session", label: I18n.tr("Don't save")}
                ]
                current: page.opts.dictationHistory
                dirty: page.dirty("dictationHistory")
                hint: I18n.tr("On this computer only. Words that could not be typed are kept until you type them again or delete them.")
                onPicked: value => page.setOpt("dictationHistory", value)
                onResetRequested: page.resetOpt("dictationHistory")
            }

            SwitchRow {
                width: parent.width
                label: I18n.tr("Keep recordings")
                description: I18n.tr("Saves the audio with each dictation, so it can be played back or transcribed again with another speech model.")
                checked: page.opts.dictationKeepAudio
                dirty: page.dirty("dictationKeepAudio")
                onToggled: value => page.setOpt("dictationKeepAudio", value)
                onResetRequested: page.resetOpt("dictationKeepAudio")
            }

            ActionRow {
                width: parent.width
                property bool confirming: false

                SettingsAction {
                    text: Dictation.historyEntries.length > 0
                        ? I18n.format(I18n.tr("Open history (%1)"), [Dictation.historyEntries.length])
                        : I18n.tr("Open history")
                    glyph: "history"
                    onTriggered: {
                        Settings.closePanel();
                        Dictation.openHistory();
                    }
                }
                SettingsAction {
                    visible: Dictation.historyEntries.length > 0
                    text: parent.confirming ? I18n.tr("Clear all dictations?") : I18n.tr("Clear history")
                    glyph: "delete"
                    danger: true
                    onTriggered: {
                        if (parent.confirming) {
                            Dictation.clearHistory();
                            parent.confirming = false;
                        } else {
                            parent.confirming = true;
                            confirmReset.restart();
                        }
                    }
                }
                Timer {
                    id: confirmReset
                    interval: 4000
                    onTriggered: parent.confirming = false
                }
            }
        }
    }
}
