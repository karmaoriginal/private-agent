package com.orailnoor.privateagent

import android.app.assist.AssistContent
import android.app.assist.AssistStructure
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.service.voice.VoiceInteractionSession
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView

/**
 * La pieza real: dibuja el overlay flotante (el "voice plate"),
 * maneja mostrar/ocultar y decide qué hacer con lo que dice el usuario.
 *
 * La vista se construye en Kotlin (sin layout XML).
 */
class AgentVoiceInteractionSession(context: Context) : VoiceInteractionSession(context) {

    private var statusText: TextView? = null

    override fun onCreateContentView(): View {
        // ---- Voice plate (overlay flotante) ----
        val root = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(48, 32, 48, 32)
            background = GradientDrawable().apply {
                cornerRadius = 48f
                setColor(Color.parseColor("#F21C1C22"))
            }
        }

        val pulse = ProgressBar(context).apply {
            isIndeterminate = true
        }

        statusText = TextView(context).apply {
            text = "Escuchando…"
            setTextColor(Color.WHITE)
            textSize = 16f
            gravity = Gravity.CENTER
        }

        root.addView(pulse)
        root.addView(statusText)
        return root
    }

    override fun onShow(args: Bundle?, showFlags: Int) {
        super.onShow(args, showFlags)
        statusText?.text = "Escuchando…"
        // TODO: arrancar la escucha (RecognitionService / motor propio)
    }

    override fun onHandleAssist(
        data: Bundle?,
        structure: AssistStructure?,
        content: AssistContent?
    ) {
        // TODO: procesar el contexto de pantalla y la petición del usuario,
        // y reenviarlo al agente (MainActivity / canal de Flutter).
        finish()
    }

    override fun onHide() {
        super.onHide()
        // TODO: detener la escucha si sigue activa
    }
}
