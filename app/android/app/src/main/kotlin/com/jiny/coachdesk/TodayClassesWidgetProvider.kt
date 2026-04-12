package com.jiny.coachdesk

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray

private data class WidgetRow(
    val primary: String,
    val secondary: String,
    val status: String,
)

abstract class TodayClassesWidgetProvider : HomeWidgetProvider() {
    abstract val widgetTitle: String
    abstract val widgetSubtitle: String
    abstract val accessKey: String
    abstract val itemsKey: String
    abstract val updatedAtKey: String
    abstract val accessDeniedMessage: String
    abstract val emptyMessage: String

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.today_classes_widget)
            val launchIntent = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
            views.setOnClickPendingIntent(R.id.widget_root, launchIntent)

            views.setTextViewText(R.id.widget_title, widgetTitle)
            views.setTextViewText(R.id.widget_subtitle, widgetSubtitle)

            val updatedAt = widgetData.getString(updatedAtKey, null)
            if (updatedAt.isNullOrBlank()) {
                views.setViewVisibility(R.id.widget_updated_at, View.GONE)
            } else {
                views.setViewVisibility(R.id.widget_updated_at, View.VISIBLE)
                views.setTextViewText(R.id.widget_updated_at, "$updatedAt 기준")
            }

            val hasAccess = widgetData.getBoolean(accessKey, false)
            val rows = parseRows(widgetData.getString(itemsKey, "[]"))

            when {
                !hasAccess -> {
                    bindEmptyState(views, accessDeniedMessage)
                }
                rows.isEmpty() -> {
                    bindEmptyState(views, emptyMessage)
                }
                else -> {
                    views.setViewVisibility(R.id.widget_empty_text, View.GONE)
                    bindRows(views, rows)
                }
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun bindEmptyState(views: RemoteViews, message: String) {
        views.setViewVisibility(R.id.widget_empty_text, View.VISIBLE)
        views.setTextViewText(R.id.widget_empty_text, message)
        rowIds().forEach { rowId ->
            views.setViewVisibility(rowId, View.GONE)
        }
    }

    private fun bindRows(views: RemoteViews, rows: List<WidgetRow>) {
        val rowIds = rowIds()
        val primaryIds = primaryIds()
        val secondaryIds = secondaryIds()
        val statusIds = statusIds()

        rowIds.forEachIndexed { index, rowId ->
            val row = rows.getOrNull(index)
            if (row == null) {
                views.setViewVisibility(rowId, View.GONE)
                return@forEachIndexed
            }

            views.setViewVisibility(rowId, View.VISIBLE)
            views.setTextViewText(primaryIds[index], row.primary)
            views.setTextViewText(secondaryIds[index], row.secondary)
            views.setTextViewText(statusIds[index], row.status)
        }
    }

    private fun parseRows(raw: String?): List<WidgetRow> {
        if (raw.isNullOrBlank()) return emptyList()

        return try {
            val array = JSONArray(raw)
            buildList {
                for (index in 0 until array.length()) {
                    val item = array.optJSONObject(index) ?: continue
                    add(
                        WidgetRow(
                            primary = item.optString("primary"),
                            secondary = item.optString("secondary"),
                            status = item.optString("status"),
                        ),
                    )
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun rowIds() = listOf(
        R.id.widget_row_1,
        R.id.widget_row_2,
        R.id.widget_row_3,
        R.id.widget_row_4,
    )

    private fun primaryIds() = listOf(
        R.id.widget_row_1_primary,
        R.id.widget_row_2_primary,
        R.id.widget_row_3_primary,
        R.id.widget_row_4_primary,
    )

    private fun secondaryIds() = listOf(
        R.id.widget_row_1_secondary,
        R.id.widget_row_2_secondary,
        R.id.widget_row_3_secondary,
        R.id.widget_row_4_secondary,
    )

    private fun statusIds() = listOf(
        R.id.widget_row_1_status,
        R.id.widget_row_2_status,
        R.id.widget_row_3_status,
        R.id.widget_row_4_status,
    )
}

class AdminTodayClassesWidgetProvider : TodayClassesWidgetProvider() {
    override val widgetTitle = "관리자 위젯"
    override val widgetSubtitle = "오늘 예약된 고객과 시간"
    override val accessKey = "widget_admin_has_access"
    override val itemsKey = "widget_admin_items"
    override val updatedAtKey = "widget_admin_updated_at"
    override val accessDeniedMessage = "관리자 계정으로 로그인하면 위젯을 사용할 수 있어요."
    override val emptyMessage = "오늘 예약된 수업이 없어요."
}

class MemberTodayClassesWidgetProvider : TodayClassesWidgetProvider() {
    override val widgetTitle = "회원 위젯"
    override val widgetSubtitle = "오늘 예약된 수업"
    override val accessKey = "widget_member_has_access"
    override val itemsKey = "widget_member_items"
    override val updatedAtKey = "widget_member_updated_at"
    override val accessDeniedMessage = "회원 계정으로 로그인하면 위젯을 사용할 수 있어요."
    override val emptyMessage = "오늘 예약된 수업이 없어요."
}
