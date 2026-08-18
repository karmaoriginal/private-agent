package com.orailnoor.privateagent

import android.os.Bundle
import android.service.voice.VoiceInteractionSession
import android.service.voice.VoiceInteractionSessionService

/**
 * Crea una nueva sesión de interacción cada vez que se activa el gesto
 * del asistente (botón, deslizar desde la esquina, etc.).
 */
class AgentVoiceInteractionSessionService : VoiceInteractionSessionService() {

    override fun onNewSession(args: Bundle?): VoiceInteractionSession {
        return AgentVoiceInteractionSession(this)
    }
}
