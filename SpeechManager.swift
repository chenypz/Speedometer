import Foundation
import AVFoundation

class SpeechManager: ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    
    // 目前選擇的語系代碼
    @Published var currentLanguage: String = "zh-TW" {
        didSet {
            UserDefaults.standard.set(currentLanguage, forKey: "AppLanguage")
        }
    }
    
    init() {
        if let savedLang = UserDefaults.standard.string(forKey: "AppLanguage") {
            self.currentLanguage = savedLang
        }
    }
    
    // 播報文字
    func speak(_ text: String) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: currentLanguage)
        utterance.rate = 0.5 // 語速
        synthesizer.speak(utterance)
    }
    
    // 警示播報
    func announceWarning(speedLimit: Int, isOverspeed: Bool) {
        let text: String
        if currentLanguage.starts(with: "zh") {
            if isOverspeed {
                text = "注意，您已超速！前方速限 \(speedLimit) 公里"
            } else {
                text = "前方速限 \(speedLimit) 公里"
            }
        } else {
            if isOverspeed {
                text = "Warning! Speed limit is \(speedLimit). You are speeding!"
            } else {
                text = "Speed limit is \(speedLimit)."
            }
        }
        speak(text)
    }
}
