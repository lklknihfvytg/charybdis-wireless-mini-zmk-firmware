#Requires AutoHotkey v2.0 64-bit
#SingleInstance Force

; Track physical modifiers while Send temporarily releases/restores Shift.
; Disable key history: no typed text is retained by the hook.
KeyHistory 0
InstallKeybdHook

SetInputLang(TargetLang)
{
    currentLayout := DllCall("GetKeyboardLayout", "UInt", 0)
    if (currentLayout != TargetLang){
        WinHnd := WinExist("A")
        if not WinHnd {
            return
        }
        CtrlInFocus := ControlGetFocus()
        if not CtrlInFocus {
            PostMessage(0x50, 0, TargetLang)
            return
        }
        PostMessage(0x50, 0, TargetLang, CtrlInFocus)
    }
}

+F14::SetInputLang(0x0409) ; English (US) ::SetInputLang(0x0809) ; English (UK)

+F13::SetInputLang(0x0419) ; Russian

+F15::Send "."
+F16::Send ","
+F17::Send "?"
+F18::Send "/"
