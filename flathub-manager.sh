#!/bin/bash
# Flathub 软件管理 v1.7 (分组查看 + 点击识别 + 应用卸载，官方unused判断)

[ -z "$DISPLAY" ] && export DISPLAY=:0
[ -z "$WAYLAND_DISPLAY" ] && export WAYLAND_DISPLAY=wayland-0
[ -z "$XDG_RUNTIME_DIR" ] && export XDG_RUNTIME_DIR=/run/user/1000

PROTECTED="org.kde.Platform org.freedesktop.Platform org.freedesktop.Platform.GL.default org.freedesktop.Platform.Locale org.kde.Platform.Locale org.freedesktop.Platform.codecs-extra org.freedesktop.Platform.openh264"

is_protected() {
    for p in $PROTECTED; do
        [[ "$1" == *"$p"* ]] && return 0
    done
    return 1
}

# 格式化字节数为MB
format_mb() {
    local bytes="$1"
    python3 -c "b=$bytes; print(f'{b/1048576:.0f} MB' if b>=1048576 else f'{b/1048576:.1f} MB' if b>0 else '-')" 2>/dev/null || echo "-"
}

# 通过ref获取大小(MB)
get_size_mb() {
    local ref="$1"
    local bytes

    # 方法1: flatpak info --show-size
    bytes=$(flatpak info --show-size "$ref" 2>/dev/null)
    if [[ "$bytes" =~ ^[0-9]+$ ]] && [ "$bytes" -gt 0 ]; then
        format_mb "$bytes"
        return
    fi

    # 方法2: flatpak info --show-location + du -sb
    local loc
    loc=$(flatpak info --show-location "$ref" 2>/dev/null)
    if [ -n "$loc" ] && [ -d "$loc" ]; then
        bytes=$(du -sb "$loc" 2>/dev/null | cut -f1)
        if [[ "$bytes" =~ ^[0-9]+$ ]] && [ "$bytes" -gt 0 ]; then
            format_mb "$bytes"
            return
        fi
    fi

    echo "-"
}

# 根据安装类型获取安装时间
get_install_time() {
    local type="$1"
    local app_id="$2"
    local installation="$3"
    local path

    if [ "$installation" = "user" ]; then
        if [ "$type" = "app" ]; then
            path="$HOME/.local/share/flatpak/app/$app_id/"
        else
            path="$HOME/.local/share/flatpak/runtime/$app_id/"
        fi
    else
        if [ "$type" = "app" ]; then
            path="/var/lib/flatpak/app/$app_id/"
        else
            path="/var/lib/flatpak/runtime/$app_id/"
        fi
    fi

    stat -c %y "$path" 2>/dev/null | cut -d'.' -f1 || echo "-"
}

# 用python3处理flatpak list的tab输出，避免空字段导致bash列偏移
flatpak_list_pipe() {
    flatpak list "$@" 2>/dev/null | python3 -c '
import sys
for line in sys.stdin:
    line = line.rstrip("\n")
    cols = line.split("\t")
    print("|".join(cols))
'
}

# 构建flatpak官方判断的unused runtime列表
# 安全：输入n取消，不会真的卸载
build_unused_runtime_file() {
    UNUSED_RT_FILE=$(mktemp)
    > "$UNUSED_RT_FILE"
    UNUSED_RT_INFO_FILE=$(mktemp)
    > "$UNUSED_RT_INFO_FILE"

    # 格式: runtime_id|branch (用于is_unused_runtime匹配)
    printf 'n\n' | flatpak uninstall --unused 2>/dev/null | awk '
        /^[[:space:]]*[0-9]+[.][[:space:]]+/ && $4 == "r" {
            print $2 "|" $3
        }
    ' >> "$UNUSED_RT_FILE"

    # 格式: runtime_id|branch|ref (用于显示缓存里没有的runtime)
    printf 'n\n' | flatpak uninstall --unused 2>/dev/null | awk '
        /^[[:space:]]*[0-9]+[.][[:space:]]+/ && $4 == "r" {
            ref = "runtime/" $2 "/aarch64/" $3
            print $2 "|" $3 "|" ref
        }
    ' >> "$UNUSED_RT_INFO_FILE"
}

# 判断runtime是否是flatpak官方标记的unused
is_unused_runtime() {
    local rt_id="$1"
    local rt_branch="$2"
    grep -q "^${rt_id}|${rt_branch}$" "$UNUSED_RT_FILE" 2>/dev/null
}

# 从runtime id提取所属平台base
get_platform_base() {
    local rt_id="$1"
    case "$rt_id" in
        org.freedesktop.Platform.GL.*|org.freedesktop.Platform.Locale|org.freedesktop.Platform.openh264|org.freedesktop.Platform.codecs-extra)
            echo "org.freedesktop.Platform"
            ;;
        org.kde.Platform.Locale|org.kde.Platform.*)
            echo "org.kde.Platform"
            ;;
        *)
            echo "$rt_id"
            ;;
    esac
}

# 判断runtime是否被某个app使用（id + branch同时匹配）
runtime_used_by_app() {
    local rt_id="$1"
    local rt_branch="$2"
    local app_rt_id="$3"
    local app_rt_branch="$4"

    if [ "$rt_id" = "$app_rt_id" ] && [ "$rt_branch" = "$app_rt_branch" ]; then
        return 0
    fi

    local rt_base
    rt_base=$(get_platform_base "$rt_id")
    if [ "$rt_base" = "$app_rt_id" ] && [ "$rt_branch" = "$app_rt_branch" ]; then
        return 0
    fi

    return 1
}

# 判断runtime是否被任何app使用
runtime_used_by_any_app() {
    local rt_id="$1"
    local rt_branch="$2"
    local ruwa_app ruwa_rt_id ruwa_rt_branch

    while IFS='|' read -r ruwa_app ruwa_rt_id ruwa_rt_branch; do
        if runtime_used_by_app "$rt_id" "$rt_branch" "$ruwa_rt_id" "$ruwa_rt_branch"; then
            return 0
        fi
    done < "$APP_RT_FILE" 2>/dev/null

    return 1
}

# 清理未使用运行时（可复用函数）
# 自动重新打开管理器
restart_manager() {
    exec "$0"
}
cleanup_unused_runtimes() {
    local installation="$1"
    local CLEAN_CMD

    if [ "$installation" = "user" ]; then
        CLEAN_CMD=(flatpak uninstall -y --user --unused)
    else
        if command -v pkexec >/dev/null 2>&1; then
            CLEAN_CMD=(pkexec flatpak uninstall -y --system --unused)
        else
            CLEAN_CMD=(flatpak uninstall -y --system --unused)
        fi
    fi

    local tmp_out
    tmp_out=$(mktemp)
    {
        echo "执行命令：${CLEAN_CMD[*]}"
        echo
        "${CLEAN_CMD[@]}" 2>&1
        echo
        echo "退出码：$?"
    } > "$tmp_out" 2>&1

    zenity --text-info --title="清理结果" --width=800 --height=500 --filename="$tmp_out" 2>/dev/null
    rm -f "$tmp_out"
}

# 行映射文件：编号→类型+ref+installation
ROW_MAP_FILE=$(mktemp)
> "$ROW_MAP_FILE"

# 构建zenity行，9个字段 + 写映射(含ref和installation)
add_row() {
    local num="$1" name="$2" appid="$3" ver="$4" type="$5" status="$6" rt="$7" sz="$8" it="$9"
    shift 9
    local ref="${1:--}" inst="${2:--}" map_type="${3:-$type}"
    ITEMS="${ITEMS} ${num} \"${name}\" \"${appid}\" \"${ver}\" \"${type}\" \"${status}\" \"${rt}\" \"${sz}\" \"${it}\""
    # 写映射：编号|类型|名称|应用ID|版本|状态|运行时|大小|安装时间|ref|installation
    echo "${num}|${map_type}|${name}|${appid}|${ver}|${status}|${rt}|${sz}|${it}|${ref}|${inst}" >> "$ROW_MAP_FILE"
}

# 分隔行 + 分组标题行
add_group_row() {
    local title="$1"
    COUNTER=$((COUNTER+1))
    add_row "$COUNTER" "────────────────" "────────────" "──────" "────" "────────" "────────────" "──────" "──────────" "-" "-" "分隔"
    COUNTER=$((COUNTER+1))
    add_row "$COUNTER" "$title" "-" "-" "分组" "-" "-" "-" "-" "-" "-"
}

# ========== 构建unused runtime列表 ==========
build_unused_runtime_file

# ========== 缓存构建 ==========

CACHE_FILE="/tmp/flathub-cache-$(id -u)"
> "$CACHE_FILE"

# 获取app
flatpak_list_pipe --app --columns=ref,name,application,version,installation | while IFS='|' read -r ref name app ver inst; do
    [ -z "$app" ] && continue
    branch=$(echo "$ref" | cut -d'/' -f3)
    rt=$(flatpak info --show-runtime "$ref" 2>/dev/null || true)
    if [ -z "$rt" ]; then
        rt=$(flatpak info "$app" 2>/dev/null | grep -E "运行时|Runtime" | head -1 | sed 's/.*运行时[：:]*[[:space:]]*//' | sed 's/.*Runtime[：:]*[[:space:]]*//' | xargs)
    fi
    install_time=$(get_install_time "app" "$app" "$inst")
    echo "${app}|${name}|${ver:-N/A}|${inst}|${branch}|${rt}|${ref}|app|${install_time}" >> "$CACHE_FILE"
done

# 获取runtime
flatpak_list_pipe --runtime --columns=ref,name,application,version,installation | while IFS='|' read -r ref name app ver inst; do
    [ -z "$app" ] && continue
    branch=$(echo "$ref" | cut -d'/' -f3)
    install_time=$(get_install_time "runtime" "$app" "$inst")
    echo "${app}|${name}|${ver:-N/A}|${inst}|${branch}||${ref}|runtime|${install_time}" >> "$CACHE_FILE"
done

# ========== 收集app的runtime信息 ==========

APP_RT_FILE=$(mktemp)
> "$APP_RT_FILE"
while IFS='|' read -r app name ver inst branch rt ref atype install_time; do
    [ "$atype" != "app" ] && continue
    rt_id=$(echo "$rt" | cut -d'/' -f1)
    rt_branch=$(echo "$rt" | cut -d'/' -f3)
    [ -n "$rt_id" ] && echo "${app}|${rt_id}|${rt_branch}" >> "$APP_RT_FILE"
done < "$CACHE_FILE"

# ========== 调试: 运行时分类判断 ==========
if [ "${FLATHUB_DEBUG:-0}" = "1" ]; then
    echo "===== RUNTIME CLASSIFICATION DEBUG ====="
    printf "%-50s %-12s %-15s %-12s %-18s %s\n" "RUNTIME_ID" "BRANCH" "USED_BY_APP" "PROTECTED" "UNUSED_BY_FLATPAK" "FINAL_GROUP"
    while IFS='|' read -r app name ver inst branch rt ref atype install_time; do
        [ "$atype" != "runtime" ] && continue
        used="no"
        used_by=""
        while IFS='|' read -r a_app a_rt_id a_rt_branch; do
            if runtime_used_by_app "$app" "$branch" "$a_rt_id" "$a_rt_branch"; then
                used="yes"
                used_by="$a_app"
                break
            fi
        done < "$APP_RT_FILE" 2>/dev/null
        prot="no"
        is_protected "$app" && prot="yes"
        unused="no"
        is_unused_runtime "$app" "$branch" && unused="yes"
        if [ "$unused" = "yes" ]; then
            group="孤立运行时"
        elif [ "$used" = "yes" ]; then
            group="应用依赖"
        elif [ "$prot" = "yes" ]; then
            group="Flatpak保留运行时"
        else
            group="Flatpak保留运行时"
        fi
        printf "%-50s %-12s %-15s %-12s %-18s %s\n" "$app" "$branch" "${used}(${used_by:-none})" "$prot" "$unused" "$group"
    done < "$CACHE_FILE"
    echo "===== UNUSED_RT_FILE ====="
    cat "$UNUSED_RT_FILE" 2>/dev/null || echo "(empty)"
    echo "===== UNUSED_RT_INFO_FILE ====="
    cat "$UNUSED_RT_INFO_FILE" 2>/dev/null || echo "(empty)"

    echo "===== ORPHAN DISPLAY CANDIDATES ====="
    while IFS='|' read -r app name ver inst branch rt ref atype install_time; do
        [ "$atype" != "runtime" ] && continue
        if is_unused_runtime "$app" "$branch"; then
            echo "ORPHAN_DISPLAY_CANDIDATE $app $branch $ref shown=yes"
        fi
    done < "$CACHE_FILE"

    rm -f "$APP_RT_FILE" "$CACHE_FILE" "$UNUSED_RT_FILE" "$UNUSED_RT_INFO_FILE" "$ROW_MAP_FILE"
    exit 0
fi

# ========== 构建分组列表 ==========

ITEMS=""
COUNTER=0

# === 组1: 🧭 应用依赖关系 ===
add_group_row "🧭 应用依赖关系"

while IFS='|' read -r app name ver inst branch rt ref atype install_time; do
    [ "$atype" != "app" ] && continue

    # 应用主行
    COUNTER=$((COUNTER+1))
    rt_short=$(echo "$rt" | cut -d'/' -f1)
    [ -n "$rt_short" ] && rt_display="🔧 $rt_short" || rt_display="-"
    sz=$(get_size_mb "$ref")
    [ -n "$install_time" ] && it_display="$install_time" || it_display="-"
    add_row "$COUNTER" "📦 $name" "$app" "$ver" "应用" "✅ 可管理" "$rt_display" "$sz" "$it_display" "$ref" "$inst"

    # 获取此app的runtime信息
    rt_id=$(echo "$rt" | cut -d'/' -f1)
    rt_branch=$(echo "$rt" | cut -d'/' -f3)

    # 遍历所有runtime，找相关的（被此app使用的）
    while IFS='|' read -r r_app r_name r_ver r_inst r_branch r_rt r_ref r_atype r_it; do
        [ "$r_atype" != "runtime" ] && continue
        if runtime_used_by_app "$r_app" "$r_branch" "$rt_id" "$rt_branch"; then
            COUNTER=$((COUNTER+1))
            r_sz=$(get_size_mb "$r_ref")
            [ -n "$r_it" ] && r_it_display="$r_it" || r_it_display="-"
            add_row "$COUNTER" "  └─ 🔧 $r_app/$r_branch" "$r_app" "$r_ver" "应用依赖" "依赖项" "-" "$r_sz" "$r_it_display" "$r_ref" "$r_inst"
        fi
    done < "$CACHE_FILE"

done < "$CACHE_FILE"

# === 组2: 🛡 Flatpak 保留运行时 ===
add_group_row "🛡 Flatpak 保留运行时"

while IFS='|' read -r app name ver inst branch rt ref atype install_time; do
    [ "$atype" != "runtime" ] && continue
    if ! is_unused_runtime "$app" "$branch"; then
        if is_protected "$app" && ! runtime_used_by_any_app "$app" "$branch"; then
            COUNTER=$((COUNTER+1))
            sz=$(get_size_mb "$ref")
            [ -n "$install_time" ] && it_display="$install_time" || it_display="-"
            add_row "$COUNTER" "⚙ $name" "$app" "$ver" "保留运行时" "🔴 受保护" "-" "$sz" "$it_display" "$ref" "$inst"
        fi
    fi
done < "$CACHE_FILE"

# === 组3: 🧩 孤立运行时 ===
add_group_row "🧩 孤立运行时"

while IFS='|' read -r app name ver inst branch rt ref atype install_time; do
    [ "$atype" != "runtime" ] && continue
    if is_unused_runtime "$app" "$branch"; then
        COUNTER=$((COUNTER+1))
        sz=$(get_size_mb "$ref")
        [ -n "$install_time" ] && it_display="$install_time" || it_display="-"
        status="⚠️ 孤立"
        add_row "$COUNTER" "⚙ $name" "$app" "$branch" "孤立运行时" "$status" "-" "$sz" "$it_display" "$ref" "$inst"
    fi
done < "$CACHE_FILE"

# 显示缓存中不存在但 flatpak uninstall --unused 列出的孤立运行时
# （例如 org.freedesktop.Locale 等 extension runtime）
while IFS='|' read -r urt_id urt_branch urt_ref; do
    [ -z "$urt_id" ] && continue
    # 检查是否已经在缓存循环里显示过（通过检查ROW_MAP_FILE里有没有这个id|branch）
    if grep -q "|孤立运行时|.*|${urt_id}|${urt_branch}|" "$ROW_MAP_FILE" 2>/dev/null; then
        continue
    fi
    COUNTER=$((COUNTER+1))
    urt_sz=$(get_size_mb "$urt_ref")
    add_row "$COUNTER" "⚙ ${urt_id}" "$urt_id" "$urt_branch" "孤立运行时" "⚠️ 孤立" "-" "$urt_sz" "-" "$urt_ref" "system"
done < "$UNUSED_RT_INFO_FILE"

rm -f "$APP_RT_FILE" "$CACHE_FILE" "$UNUSED_RT_FILE" "$UNUSED_RT_INFO_FILE"

if [ $COUNTER -eq 0 ]; then
    zenity --info --title="Flathub管理" --text="没有已安装的Flatpak应用" 2>/dev/null
    rm -f "$ROW_MAP_FILE"
    exit 0
fi

# ========== 显示列表 + 点击识别 ==========
SELECTED_NUM=$(eval zenity --list --title=\"Flathub软件管理\" \
    --width=1050 --height=500 \
    --print-column=1 \
    --column="#" --column="名称" --column="应用ID" --column="版本" --column="类型" --column="状态" --column="运行时/归属" --column="大小" --column="安装时间" \
    $ITEMS 2>/dev/null) || { rm -f "$ROW_MAP_FILE"; exit 0; }

[ -z "$SELECTED_NUM" ] && { rm -f "$ROW_MAP_FILE"; exit 0; }

# 根据编号查映射文件
ROW=$(grep "^${SELECTED_NUM}|" "$ROW_MAP_FILE" | head -n 1 || true)
rm -f "$ROW_MAP_FILE"

[ -z "$ROW" ] && exit 0

# 解析映射行（含ref和installation）
IFS='|' read -r row_num row_type row_name row_appid row_ver row_status row_rt row_size row_time row_ref row_installation <<< "$ROW"

# 根据类型处理
case "$row_type" in
    "分隔")
        restart_manager
        ;;
    "分组")
        restart_manager
        ;;
    "应用依赖")
        zenity --info --title="应用依赖运行时" --text="这是某个应用正在使用的运行时，不能单独从这里卸载。\n\n如果要清理运行时，请先卸载对应应用，然后运行 flatpak uninstall --unused。" 2>/dev/null
        restart_manager
        ;;
    "保留运行时")
        zenity --warning --title="Flatpak 保留运行时" --text="此运行时当前未被 Flatpak 标记为可清理项，本工具暂不允许卸载。\n\n如需检查未使用运行时，请使用 flatpak uninstall --unused。" 2>/dev/null
        restart_manager
        ;;
    "孤立运行时")
        # 弹确认框：清理全部孤立运行时
        zenity --question --title="清理孤立运行时" \
            --text="当前选择的是：\n名称：${row_name}\nID：${row_appid}\n分支/版本：${row_ver}\n大小：${row_size}\n\n本工具将运行：\nflatpak uninstall --unused\n\n这会清理 Flatpak 判断为未使用的所有运行时，而不是只清理当前这一条。\n确认继续吗？" \
            --ok-label="清理" --cancel-label="取消" 2>/dev/null

        if [ $? -ne 0 ]; then
            exit 0
        fi

        # 执行清理
        local_install="${row_installation}"
        [ -z "$local_install" ] || [ "$local_install" = "-" ] && local_install="system"
        cleanup_unused_runtimes "$local_install"

        zenity --info --title="清理完成" --text="清理完成。正在重新打开管理器查看最新列表。" 2>/dev/null
        restart_manager
        ;;
    "应用")
        # 确认卸载
        zenity --question --title="卸载应用" \
            --text="名称：${row_name}\nID：${row_appid}\n版本：${row_ver}\n安装位置：${row_installation}\n大小：${row_size}\n安装时间：${row_time}\nREF：${row_ref}\n\n确认卸载这个 Flatpak 应用吗？\n卸载后会再询问是否清理未使用运行时。" \
            --ok-label="卸载" --cancel-label="取消" 2>/dev/null

        if [ $? -ne 0 ]; then
            exit 0
        fi

        # 执行卸载
        if [ "$row_installation" = "user" ]; then
            CMD=(flatpak uninstall -y --user "$row_appid")
        else
            if command -v pkexec >/dev/null 2>&1; then
                CMD=(pkexec flatpak uninstall -y --system "$row_appid")
            else
                CMD=(flatpak uninstall -y --system "$row_appid")
            fi
        fi

        TMP_OUT=$(mktemp)
        {
            echo "执行命令：${CMD[*]}"
            echo
            "${CMD[@]}" 2>&1
            echo
            echo "退出码：$?"
        } > "$TMP_OUT" 2>&1

        # 检查卸载是否成功：查看输出文件里的退出码
        if grep -q "退出码：0" "$TMP_OUT" 2>/dev/null; then
            UNINSTALL_OK=1
        else
            # fallback：检查应用是否还在flatpak list里
            if ! flatpak list --app --columns=application 2>/dev/null | grep -q "^${row_appid}$"; then
                UNINSTALL_OK=1
            else
                UNINSTALL_OK=0
            fi
        fi

        zenity --text-info --title="卸载结果" --width=800 --height=500 --filename="$TMP_OUT" 2>/dev/null
        rm -f "$TMP_OUT"

        # 如果卸载成功，询问是否清理unused runtime
        if [ "$UNINSTALL_OK" = "1" ]; then
            zenity --question --title="清理未使用运行时" \
                --text="应用已卸载。\n是否运行 flatpak uninstall --unused 来清理当前未使用的运行时？\n该命令会由 Flatpak 自己判断哪些运行时可清理。" \
                --ok-label="清理" --cancel-label="不清理" 2>/dev/null

            if [ $? -eq 0 ]; then
                cleanup_unused_runtimes "$row_installation"
            fi
            restart_manager
        fi
        ;;
    *)
        zenity --info --title="未知项目" --text="未识别的项目类型：${row_type}" 2>/dev/null
        ;;
esac
