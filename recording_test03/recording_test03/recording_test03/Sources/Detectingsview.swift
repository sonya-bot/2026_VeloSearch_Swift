import SwiftUI
import AudioToolbox
import Foundation
import AVFoundation
import SwiftUI
import Observation
import CoreML


// MARK: - 0. Preview(Xcode)
struct DetectingsView_Previews: PreviewProvider {
  static var previews: some View {
    DetectingsView()
  }
}

enum DetectionState {
    case standby
    case safe
    case detect
    
    var title: String {
        switch self {
        case .standby: return "Standby"
        case .safe: return "Safe"
        case .detect: return "Detect"
        }
    }
    var themeColor: Color {
        switch self {
        case .standby: return .secondary
        case .safe: return .green
        case .detect: return .red
        }
    }
}

// MARK: - 1. Detecting (検知ロジック)
@Observable
class Detection {
    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    
    private let featureExtractor = AudioFeatureExtractor()
    private let mlManager = MLModelManager()
    
    var isRecording = false
    var state: DetectionState = .standby
    var elapsedTime: TimeInterval = 0.0
    var currentDecibel: Float = -160.0
    
    var currentAIAngle: Int = 0
    var currentAIProbability: Float = 0.0
    var currentGroundTruth: String = "FalseDetect" // ピッカー選択値

    // ===== デバッグ情報 =====
    var debugBufferCount: Int = 0
    var debugFeatureCreated: Bool = false
    var debugPredictExecuted: Bool = false
    var debugPredictSuccess: Bool = false
    var debugMessage: String = ""
    
    private var timer: Timer?
    private var startTime: Date?
    private var speedcsvTimer: Timer?
    private var speedcsvData: [String] = []
    private var currentBaseFileName: String = ""
    private var currentOrientation: String = "横"
    private var currentMicSource: String = "背面"
    
    func startDetecting(locationManager: LocationManager, orientation: String, micSource: String) {
        self.currentOrientation = orientation
        self.currentMicSource = micSource
        let audioSession = AVAudioSession.sharedInstance()
        let fileManager = FileManager.default
        let documentPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let dateString = formatter.string(from: Date())
        let nextNum = getNextSequenceNumber(dateString: dateString, in: documentPath)
        
        self.currentBaseFileName = "Detecting_\(dateString)_\(String(format: "%02d", nextNum))"
        let audioFilename = documentPath.appendingPathComponent("\(self.currentBaseFileName).wav")
        
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try audioSession.setActive(true)
            
            let inputNode = audioEngine.inputNode
            let inputFormat = inputNode.inputFormat(forBus: 0)
            
            audioFile = try AVAudioFile(forWriting: audioFilename, settings: inputFormat.settings)
            
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] (buffer, time) in
                guard let self = self else { return }
                do { try self.audioFile?.write(from: buffer) } catch { print("WAV Error") }
                
                self.calculateDecibel(buffer: buffer)
                
                // 特徴量抽出と推論
                self.debugBufferCount = self.featureExtractor.currentBufferCount

                if let features = self.featureExtractor.appendAndExtract(buffer: buffer) {

                    self.debugFeatureCreated = true
                    self.executeAI(features: features)

                } else {

                    self.debugFeatureCreated = false

                }
            }
            
            audioEngine.prepare()
            try audioEngine.start()
            
            isRecording = true
            state = .safe
            elapsedTime = 0.0
            startTime = Date()
            
            speedcsvData = [
            "elapsed_time,speed_kmh,volume_db,status,ai_angle,ai_probability,ground_truth_angle,device_orientation,mic_source,buffer_count,feature_created,predict_executed,predict_success"
            ]
            
            timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
                guard let self = self, let startTime = self.startTime else { return }
                self.elapsedTime = Date().timeIntervalSince(startTime)
            }
            speedcsvTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.recordCSVLog(locationManager: locationManager)
            }
            
        } catch {
            print("録音開始失敗: \(error)")
        }
    }
    
    func stopDetecting() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioFile = nil
        isRecording = false
        state = .standby
        
        timer?.invalidate()
        speedcsvTimer?.invalidate()
        savespeedCSV()
    }
    
    private func executeAI(features: MLMultiArray) {
        debugPredictExecuted = true
        Task.detached { [weak self] in
            guard let self = self else { return }
            if let result = self.mlManager.predict(features: features) {
                Task { @MainActor in
                    self.debugPredictSuccess = true

                    self.currentAIAngle = result.angle
                    self.currentAIProbability = result.probability

                    self.state =
                        result.probability >= self.mlManager.detectionThreshold
                        ? .detect
                        : .safe
                }
            } else {
                Task { @MainActor in
                    self.debugPredictSuccess = false
                }
            }
        }
    }
    
    private func calculateDecibel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let channelDataValueArray = stride(from: 0, to: Int(buffer.frameLength), by: buffer.stride).map{ channelData[$0] }
        let rms = sqrt(channelDataValueArray.map{ $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))
        let avgPower = 20 * log10(rms)
        DispatchQueue.main.async {
            self.currentDecibel = avgPower.isNaN || avgPower.isInfinite ? -160.0 : max(avgPower, -160.0)
        }
    }
    
    private func recordCSVLog(locationManager: LocationManager) {

        let speed = locationManager.speed * 3.6

        let logLine = String(
            format: "%.2f,%.1f,%.1f,%@,%d,%.1f,%@,%@,%@,%d,%@,%@,%@",
            elapsedTime,
            speed,
            currentDecibel,
            state.title,
            currentAIAngle,
            currentAIProbability,
            currentGroundTruth,
            currentOrientation,
            currentMicSource,
            debugBufferCount,
            debugFeatureCreated.description,
            debugPredictExecuted.description,
            debugPredictSuccess.description
        )

        speedcsvData.append(logLine)
    }
    
    private func getNextSequenceNumber(dateString: String, in directory: URL) -> Int {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            return files.filter { $0.lastPathComponent.hasPrefix("Detecting_\(dateString)") }.count + 1
        } catch { return 1 }
    }
    
    private func savespeedCSV() {
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("\(currentBaseFileName).csv")
        do { try speedcsvData.joined(separator: "\n").write(to: path, atomically: true, encoding: .utf8) } catch { print("CSV Error") }
    }
}

// MARK: -2 DetentingsView(画面UI)
struct DetectingsView: View {
    @State private var detection = Detection()
    @State private var locationManager = LocationManager()
    @AppStorage("warningSoundID") private var selectedSoundID: Int = 1052
    @AppStorage("deviceOrientation") private var selectedOrientation: String = "横"
    @AppStorage("micSource") private var selectedMicSource: String = "背面"
    
    // 正解入力ピッカーの選択肢
    let truthOptions = ["FalseDetect", "0°", "45°", "90°", "135°", "180°", "225°", "270°", "315°"]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()
                
                GeometryReader { geometry in
                    let isLandscape = geometry.size.width > geometry.size.height
                
                if isLandscape {
                    // 横画面レイアウト: 左右に2分割
                    HStack(spacing: 0) {
                        // 左半分 (ステータス + レーダー)
                        VStack(spacing: 8) {
                            Spacer(minLength: 0)
                            statusView
                                .padding(.bottom, 10)
                            radarSection
                            Spacer(minLength: 0)
                        }
                        .frame(width: (geometry.size.width - 30) / 3)
                        
                        // 右半分 (速度/音量 + ピッカー + ボタン)
                        VStack(spacing: 8) {
                            Spacer(minLength: 0)
                            micAssignmentLabels
                                .padding(.top, -20)
                            groundTruthPicker
                            controlButton
                                .padding(.bottom, 8)
                            Spacer(minLength: 0)
                        }
                        .frame(width: (geometry.size.width - 30) * 2 / 3)
                    }
                } else {
                    // 縦画面レイアウト (従来通り)
                    VStack(spacing: 0) {
                        statusView
                        micAssignmentLabels
                        Spacer(minLength: 0)
                        radarSection
                        Spacer(minLength: 0)
                        groundTruthPicker
                            .padding(.bottom, 16)
                        controlButton
                            .padding(.bottom, 16)
                    }
                }
                }
            }
            .navigationTitle("Detection")
            // アラート音のトリガー
            .onChange(of: detection.state) { oldValue, newValue in
                if newValue == .detect && oldValue != .detect {
                    AudioServicesPlaySystemSound(SystemSoundID(selectedSoundID))
                }
            }
        }
    }

    // MARK: - UI Components
    private var statusView: some View {
        let statusText = detection.state == .detect ? "\(detection.state.title) (\(detection.currentAIAngle)°)" : detection.state.title
        return Text(statusText)
            .font(.system(size: 28, weight: .bold))
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.15)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(detection.state.themeColor, lineWidth: 2))
            .padding(.horizontal, 24)
            .padding(.top, 10)
    }

    private var radarSection: some View {
        RadarView(state: detection.state, aiAngle: detection.currentAIAngle)
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 220, maxHeight: 220)
    }

    // マイクの割り当て表示
    private var micAssignmentLabels: some View {
        List {
            Section(header: Text("Mic Assignment")) {
                HStack {
                    // 1. 左側: マイク設定
                    VStack(spacing: 6) {
                        Text(selectedMicSource == "背面" ? "Back" : "Front")
                        Divider()
                            .overlay(Color.gray)
                            .padding(.horizontal, 10)
                        Text("Bottom")
                    }
                    .frame(maxWidth: .infinity)
                    Spacer()

                    Divider()
                        .overlay(Color.gray)

                    // 2. 真ん中: 端末の向き
                    VStack(spacing: 6) {
                        Image(systemName: selectedOrientation == "縦" ? "iphone" : "iphone.landscape")
                            .font(.title2)
                        Text(selectedOrientation == "縦" ? "Portrait" : "Landscape")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)

                    Divider()
                        .overlay(Color.gray)

                    // 3. 右側: 音量確認
                    VStack(spacing: 6) {
                        Text("Volume").font(.caption).foregroundStyle(.secondary)
                        let decibelText = detection.currentDecibel <= -160.0 ? "0.0" : String(format: "%.1f", detection.currentDecibel)
                        Text("\(decibelText) dB").font(.title3).monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .listStyle(.insetGrouped)
        .frame(height: 125)
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
    }


    private var groundTruthPicker: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Ground Truth (正解/誤検知ラベル)").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 24)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(truthOptions, id: \.self) { option in
                        Button(action: {
                            detection.currentGroundTruth = option == "FalseDetect" ? "FalseDetect" : option.replacingOccurrences(of: "°", with: "")
                        }) {
                            Text(option == "FalseDetect" ? "誤検知" : option)
                                .font(.subheadline).bold()
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(detection.currentGroundTruth == (option == "FalseDetect" ? "FalseDetect" : option.replacingOccurrences(of: "°", with: "")) ? Color.blue : Color.gray.opacity(0.2))
                                .foregroundColor(detection.currentGroundTruth == (option == "FalseDetect" ? "FalseDetect" : option.replacingOccurrences(of: "°", with: "")) ? .white : .primary)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }

    @ViewBuilder
    private var controlButton: some View {
        Button(action: {
            withAnimation(.spring()) {
                if detection.isRecording { detection.stopDetecting() }
                else { detection.startDetecting(locationManager: locationManager, orientation: selectedOrientation, micSource: selectedMicSource) }
            }
        }) {
            Text(detection.isRecording ? "Stop" : "Start")
                .font(.title2).bold().foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(detection.isRecording ? .red : .blue)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 24)
        .sensoryFeedback(.impact(flexibility: .solid), trigger: detection.isRecording)
    }
}

// 動的レーダーUI
struct RadarView: View {
    let state: DetectionState
    let aiAngle: Int

    var body: some View {
        ZStack {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let maxRadius = size.width / 2
                for i in 1...3 {
                    let radius = maxRadius * CGFloat(i) / 3
                    context.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), with: .color(.secondary.opacity(0.2)), lineWidth: 1)
                }
                for i in 0..<8 {
                    let angle = Angle.degrees(Double(i) * 45)
                    var path = Path()
                    path.move(to: center)
                    path.addLine(to: CGPoint(x: center.x + maxRadius * cos(CGFloat(angle.radians)), y: center.y + maxRadius * sin(CGFloat(angle.radians))))
                    context.stroke(path, with: .color(.secondary.opacity(0.1)), lineWidth: 1)
                }
            }
            
            if state == .detect {
                SectorHighlight(state: state)
                    // 真上が0度になるように -90度オフセットし、AIの角度を加算して回転
                    .rotationEffect(.degrees(Double(aiAngle - 90)))
            }
            
            Circle()
                .fill(Color.gray)
                .frame(width: 40, height: 40)
                .symbolEffect(.pulse, isActive: state != .standby)
        }
    }
}

struct SectorHighlight: View {
    let state: DetectionState
    @State private var opacity = 0.8
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                let radius = geometry.size.width / 2
                path.move(to: center)
                // 45度の扇形（±22.5度）
                path.addArc(center: center, radius: radius, startAngle: .degrees(-22.5), endAngle: .degrees(22.5), clockwise: false)
                path.closeSubpath()
            }
            .fill(state.themeColor.opacity(opacity))
            .onAppear {
                withAnimation(.easeInOut(duration: 0.4).repeatForever()) { opacity = 0.3 }
            }
        }
    }
}
