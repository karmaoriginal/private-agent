package com.orailnoor.privateagent

import android.service.voice.VoiceInteractionService

/**
 * Servicio "siempre corriendo" que el sistema mantiene activo mientras
 * PrivateAgent sea el asistente de voz por defecto del dispositivo.
 */
class AgentVoiceInteractionService : VoiceInteractionService() {

    override fun onReady() {
        super.onReady()
        // El sistema nos ha vinculado como asistente activo.
    }

    override fun onShutdown() {
        super.onShutdown()
        // Ya no somos el asistente por defecto.
    }
}
