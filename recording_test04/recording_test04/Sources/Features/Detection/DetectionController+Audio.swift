import AVFoundation
import Foundation

extension DetectionController {
  @MainActor
  func toggleTestSound(_ soundSource: MonitoringSoundSource) {
    if isTestSoundPlaying {
      stopTestSound()
      return
    }

    guard
      let soundURL = Bundle.main.url(
        forResource: soundSource.fileName,
        withExtension: "wav"
      )
    else {
      AppLogger.audio.error("テスト音源が見つかりません: \(soundSource.fileName).wav")
      return
    }

    do {
      if !isRecording {
        _ = try audioIOController.configureForRecording(allowsPlayback: true)
      }
      testSoundPlayer = try AVAudioPlayer(contentsOf: soundURL)
      testSoundPlayer?.prepareToPlay()
      guard testSoundPlayer?.play() == true else {
        AppLogger.audio.error("テスト音源を再生できません: \(soundSource.fileName).wav")
        return
      }
      isTestSoundPlaying = true

      let duration = testSoundPlayer?.duration ?? 0.0
      testSoundPlaybackTask?.cancel()
      testSoundPlaybackTask = Task { @MainActor [weak self] in
        let nanoseconds = UInt64(max(duration, 0.0) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
        guard !Task.isCancelled else { return }
        self?.isTestSoundPlaying = false
        self?.testSoundPlayer = nil
      }
    } catch {
      stopTestSound()
      AppLogger.audio.error("テスト音源の再生に失敗しました: \(error.localizedDescription)")
    }
  }

  @MainActor
  func stopTestSound() {
    testSoundPlaybackTask?.cancel()
    testSoundPlaybackTask = nil
    testSoundPlayer?.stop()
    testSoundPlayer = nil
    isTestSoundPlaying = false
  }

  func configureInputSession(
    _ audioSession: AVAudioSession,
    orientation: String,
    micSource: String
  ) throws {
    // Monitoring画面と同じ条件で録音するため、
    // 内蔵マイクの面とステレオ指向性を明示する。
    if let availableInputs = audioSession.availableInputs,
      let builtInMic = availableInputs.first(where: { $0.portType == .builtInMic }),
      let dataSources = builtInMic.dataSources
    {
      let targetOrientation: AVAudioSession.Orientation = (micSource == "背面") ? .back : .front

      if let selectedDataSource = dataSources.first(where: { $0.orientation == targetOrientation })
      {
        try builtInMic.setPreferredDataSource(selectedDataSource)

        if let supportedPatterns = selectedDataSource.supportedPolarPatterns,
          supportedPatterns.contains(.stereo)
        {
          try selectedDataSource.setPreferredPolarPattern(.stereo)
        } else {
          AppLogger.audio.notice("選択したマイクはステレオ入力に対応していません")
        }

        try audioSession.setPreferredInput(builtInMic)
      }
    }

    // 端末向きはマイク選択後に反映する。順序はMonitoring画面と揃える。
    if orientation == "縦" {
      try audioSession.setPreferredInputOrientation(.portrait)
    } else {
      try audioSession.setPreferredInputOrientation(.landscapeRight)
    }
  }

  func convertBuffer(
    _ buffer: AVAudioPCMBuffer,
    converter: AVAudioConverter,
    targetFormat: AVAudioFormat
  ) -> AVAudioPCMBuffer? {
    let inputSampleRate = buffer.format.sampleRate
    guard inputSampleRate > 0 else { return nil }

    let sampleRateRatio = targetFormat.sampleRate / inputSampleRate
    let outputCapacity =
      AVAudioFrameCount(ceil(Double(buffer.frameLength) * sampleRateRatio)) + 1024
    guard
      let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity)
    else {
      return nil
    }

    var didProvideInput = false
    var conversionError: NSError?

    // 1つのtap bufferにつき入力は一度だけ供給する。返し続けると変換が不正になる。
    let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
      if didProvideInput {
        outStatus.pointee = .noDataNow
        return nil
      }

      didProvideInput = true
      outStatus.pointee = .haveData
      return buffer
    }

    if status == .error {
      if let conversionError {
        AppLogger.audio.error(
          "音声形式の変換に失敗しました: \(conversionError.localizedDescription)"
        )
      }
      return nil
    }

    return outputBuffer.frameLength > 0 ? outputBuffer : nil
  }

  func calculateDecibel(buffer: AVAudioPCMBuffer) {
    guard let channelData = buffer.floatChannelData?[0] else { return }
    let channelDataValueArray = stride(from: 0, to: Int(buffer.frameLength), by: buffer.stride).map
    { channelData[$0] }
    let rms = sqrt(channelDataValueArray.map { $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))
    let avgPower = 20 * log10(rms)
    DispatchQueue.main.async {
      self.currentDecibel = avgPower.isNaN || avgPower.isInfinite ? -160.0 : max(avgPower, -160.0)
    }
  }

}
