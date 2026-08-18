package com.orailnoor.privateagent

import android.content.Intent
import android.speech.RecognitionService
import android.speech.SpeechRecognizer

/**
 * Servicio de reconocimiento de voz propio. Android exige que un
 * asistente de voz también sea proveedor de reconocimiento.
 *
 * De momento es un stub mínimo: responde con error para no dejar
 * colgado al sistema. Sustituir por un motor real (Whisper, Vosk…).
 */
class AgentRecognitionService : RecognitionService() {

    override fun onStartListening(recognizerIntent: Intent?, listener: Callback?) {
        // TODO: iniciar reconocimiento real y reportar por `listener`
        listener?.error(SpeechRecognizer.ERROR_CLIENT)
    }

    override fun onStopListening(listener: Callback?) {
        listener?.error(SpeechRecognizer.ERROR_CLIENT)
    }

    override fun onCancel(listener: Callback?) {
        // Nada que cancelar en el stub.
    }
}
