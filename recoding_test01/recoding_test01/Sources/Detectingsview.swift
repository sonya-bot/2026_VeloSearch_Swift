import AVFoundation
import CoreLocation
import Foundation
import Observation
import AudioToolbox
import SwiftUI

// MARK: - 0. Preview(Xcode)
struct DetectingsView_Previews: PreviewProvider {
  static var previews: some View {
    DetectingsView()
  }
}

// MARK: - 1. Detection (ロジック定義)
@Observable
class Detection {
  var audioRecorder: AVAudioRecorder?

  var isRecording = false
  var state: DetectionState = .standby
  var elapsedTime: TimeInterval = 0.0
  var currentDecibel: Float = 0.0

  private var timer: Timer?
  private var levelTimer: Timer?  // 現在の音量(dB)を取得するためだけに残します
  private var startTime: Date?

  private var speedcsvTimer: Timer?
  private var speedcsvData: [String] = []
  private var currentBaseFileName: String = ""

  func startDetecting(locationManager: LocationManager) {
    let audioSession = AVAudioSession.sharedInstance()
    let fileManager = FileManager.default
    let documentPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd"
    let dateString = formatter.string(from: Date())
    let nextNumber = getNextSequenceNumber(dateString: dateString, in: documentPath)

    self.currentBaseFileName = "Detecting_\(dateString)_\(String(format: "%02d", nextNumber))"  // 録音ファイルの接頭辞は "Detecting_"
    let audioFilename = documentPath.appendingPathComponent("\(self.currentBaseFileName).wav")

    do {
      try audioSession.setCategory(.playAndRecord, mode: .default)
      try audioSession.setActive(true)

      let settings = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 44100,
        AVNumberOfChannelsKey: 2,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
      ]

      audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
      audioRecorder?.isMeteringEnabled = true
      audioRecorder?.record()

      isRecording = true
      print("録音開始: 保存先は \(self.currentBaseFileName)です")
      elapsedTime = 0.0
      startTime = Date()
      currentDecibel = 0.0
      speedcsvData = ["elapsed_time,speed_kmh,volume_db,status,type"]  // ヘッター行の定義

      timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
        guard let self = self, let startTime = self.startTime else { return }
        self.elapsedTime = Date().timeIntervalSince(startTime)
      }

      startMonitoring()

      speedcsvTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
        guard let self = self else { return }
        let time = self.elapsedTime
        let speedKmh = locationManager.speed * 3.6
        let volume = self.currentDecibel
        let status = self.state.title
        let type = ""  // 後に実装予定のため、今は空文字(検知種類を実装予定)
        let logLine = String(format: "%.2f,%.1f,%.1f,%@,%@", time, speedKmh, volume, status, type)
        self.speedcsvData.append(logLine)
      }

    } catch {
      print("録音の開始に失敗しました: \(error.localizedDescription)")
    }
  }

  private func getNextSequenceNumber(dateString: String, in directory: URL) -> Int {
    let fileManager = FileManager.default
    do {
      let files = try fileManager.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil)
      let dailyFiles = files.filter {
        $0.lastPathComponent.hasPrefix(dateString) && $0.pathExtension == "wav"
      }
      return dailyFiles.count + 1
    } catch {
      return 1
    }
  }

  func stopDetecting() {
    audioRecorder?.stop()
    isRecording = false

    timer?.invalidate()
    timer = nil
    levelTimer?.invalidate()
    levelTimer = nil
    startTime = nil
    elapsedTime = 0.0
    currentDecibel = 0.0
    speedcsvTimer?.invalidate()
    speedcsvTimer = nil

    savespeedCSV()
    print("録音停止")
  }

  private func startMonitoring() {
    levelTimer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
      guard let self = self, let recorder = self.audioRecorder else { return }

      recorder.updateMeters()
      self.currentDecibel = recorder.averagePower(forChannel: 0)
    }
  }

  private func savespeedCSV() {
    let fileManager = FileManager.default
    let documentPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let csvFilename = documentPath.appendingPathComponent("\(currentBaseFileName).csv")
    let csvString = speedcsvData.joined(separator: "\n")

    do {
      try csvString.write(to: csvFilename, atomically: true, encoding: .utf8)
      print("CSV保存完了: \(currentBaseFileName).csv")
    } catch {
      print("CSVの保存に失敗しました: \(error.localizedDescription)")
    }
  }
}

// MARK: - 2. 状態定義 (デコイ用)
enum DetectionState {
  case standby  // 待機中
  case safe  // 安全
  case detect  // 検知
  case close  // 接近
  case danger  // 危険

  var title: String {
    switch self {
    case .standby: return "Standby"
    case .safe: return "Safe"
    case .detect: return "Detect"
    case .close: return "Close"
    case .danger: return "Danger"
    }
  }

  var themeColor: Color {
    switch self {
    case .standby: return .secondary
    case .safe: return .secondary
    case .detect: return .blue
    case .close: return .yellow
    case .danger: return .red
    }
  }
}

// MARK: - 3. メイン画面 UI
struct DetectingsView: View {
  @State private var detection = Detection()
  @State private var locationManager = LocationManager()

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        // ステータステキスト
        Text(detection.state.title)
          .font(.system(size: 32))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
          .background(
            RoundedRectangle(cornerRadius: 12)
              .fill(Color.gray.opacity(0.15))
          )
          .overlay(
            RoundedRectangle(cornerRadius: 12)
              .stroke(lineWidth: 2)
          )
          .padding(.horizontal, 24)
          .padding(.top, 40)
          .contentTransition(.interpolate)

        Spacer()

        // アイコン（カスタムレーダー）
        RadarView(state: detection.state)
          .frame(width: 300, height: 300)
          .onTapGesture {
            // デコイ：システム稼働中のみ、タップで車両接近をシミュレート
            if detection.isRecording {
              cycleActiveState()
            }
          }

        Spacer()

        // サブデータ
        HStack(spacing: 30) {
          VStack(alignment: .leading) {
            Text("Speed")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text("\(String(format: "%.1f", locationManager.speed * 3.6)) km/h")
              .font(.title3)
              .monospacedDigit()
          }

          Divider().frame(height: 30)

          VStack(alignment: .leading) {
            Text("Volume")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text("\(String(format: "%.1f", detection.currentDecibel)) dB")
              .font(.title3)
              .monospacedDigit()
          }
        }
        .padding(.bottom, 60)

        // コントロール
        Button(action: {
          withAnimation(.spring()) {
            if detection.isRecording {
              // 録音停止 ＆ 強制的に待機状態へ
              detection.stopDetecting()
              detection.state = .standby
            } else {
              // 録音開始 ＆ 監視状態へ
              detection.startDetecting(locationManager: locationManager)
              detection.state = .safe
            }
          }
        }) {
          Text(detection.isRecording ? "Stop" : "Start")
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(detection.isRecording ? .red : .blue)
            .clipShape(Capsule())
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .sensoryFeedback(.impact(flexibility: .solid), trigger: detection.isRecording)
        .onChange(of: detection.state) { oldValue, newValue in
            let soundID: SystemSoundID = 1052 // 「ピッ」という汎用的なシステム音
            
            switch newValue {
            case .detect:
                // 【検知】遠くにいる時：1回だけ鳴る
                AudioServicesPlaySystemSound(soundID)
                
            case .close:
                // 【接近】近づいてきた時：2回連続で鳴る（0.2秒間隔）
                AudioServicesPlaySystemSound(soundID)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    AudioServicesPlaySystemSound(soundID)
                }
                
            case .danger:
                // 【危険】至近距離の時：3回連続で素早く鳴る
                AudioServicesPlaySystemSound(soundID)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    AudioServicesPlaySystemSound(soundID)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    AudioServicesPlaySystemSound(soundID)
                }
                
            default:
                break
            }
        }
      }
      .navigationTitle("Detectings(test)")  // デコイタイトル
    }
  }

  // デコイ：稼働中（safe, close, danger）をループする
  private func cycleActiveState() {
    withAnimation {
      switch detection.state {
      case .safe: detection.state = .detect
      case .detect: detection.state = .close
      case .close: detection.state = .danger
      case .danger: detection.state = .safe
      case .standby: break  // 待機中はタップしても何もしない
      }
    }
  }
}
// MARK: - 4. カスタムレーダー描画コンポーネント
struct RadarView: View {
  let state: DetectionState

  var body: some View {
    ZStack {
      // 背景のグリッド（8方向・3段階）
      Canvas { context, size in
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxRadius = size.width / 2

        // 3段階の同心円
        for i in 1...3 {
          let radius = maxRadius * CGFloat(i) / 3
          context.stroke(
            Path(
              ellipseIn: CGRect(
                x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .color(.secondary.opacity(0.2)),
            lineWidth: 1
          )
        }

        // 8方向の分割線
        for i in 0..<8 {
          let angle = Angle.degrees(Double(i) * 45)
          var path = Path()
          path.move(to: center)
          path.addLine(
            to: CGPoint(
              x: center.x + maxRadius * cos(CGFloat(angle.radians)),
              y: center.y + maxRadius * sin(CGFloat(angle.radians))
            ))
          context.stroke(path, with: .color(.secondary.opacity(0.1)), lineWidth: 1)
        }
      }

      // 接近時のハイライト（デコイ：真後ろのセクターを光らせる）
      if state == .detect || state == .close || state == .danger {
        SectorHighlight(state: state)
          .id(state)
          .rotationEffect(.degrees(90))  // 真後ろ方向に回転
      }

      // 中央の自機（楕円）
      Ellipse()
        .fill(state.themeColor)
        .frame(width: 40, height: 60)
        .shadow(color: state.themeColor.opacity(0.5), radius: 10)
        // 監視中のみゆっくりパルスアニメーション
        .symbolEffect(.pulse, isActive: state != .standby)
    }
  }
}

// 接近方向のハイライト描画
struct SectorHighlight: View {
  let state: DetectionState
  @State private var opacity = 0.8

  var body: some View {
    GeometryReader { geometry in
      Path { path in
        let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
        let maxRadius = geometry.size.width / 2
        let radius: CGFloat

        switch state {
        case .detect: radius = maxRadius
        case .close: radius = maxRadius * 2 / 3
        case .danger: radius = maxRadius / 3
        default: radius = 0
        }

        path.move(to: center)
        path.addArc(
          center: center, radius: radius, startAngle: .degrees(-22.5), endAngle: .degrees(22.5),
          clockwise: false)
        path.closeSubpath()
      }
      .fill(state.themeColor.opacity(opacity))
      .onAppear {
        withAnimation(.easeInOut(duration: state == .danger ? 0.2 : 0.6).repeatForever()) {
          opacity = 0.3
        }
      }
    }
  }
}
