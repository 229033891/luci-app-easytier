-- 把字段说明文字折叠成标题右侧的悬浮问号，去掉每个字段 2~3 行说明占用的纵向空间；
-- 说明原文（含 <br>、<strong>、链接）完整保留在浮层里，翻译文案不需要改动。
--
-- 支持两处结构：
--   1) LuCI CBI 表单：.cbi-value-description  → 挂到同行的 .cbi-value-title 右侧
--      （常规设置、高级设置）
--   2) 自定义模板表单：.form-group .description → 挂到同组第一个 <label> 右侧
--      （自建 Web 控制台）
--
-- 用法（CBI 的 Map）：
--   local tips_ok, tips = pcall(require, "luci.easytier_tips")
--   if tips_ok and tips then m.description = tips end
--
-- 用法（自定义模板，比如 easytier_web.htm）：
--   <% local ok, t = pcall(require, "luci.easytier_tips"); if ok and t then write(t) end %>
--
-- 浮层挂在 body 上、用 position:fixed 定位，避免被主题给 .cbi-value /
-- .cbi-value-title 设的 overflow:hidden 裁掉。

local html = [=[
<style>
/* ===== 问号图标 ===== */
.et-tip-i {
	display: inline-block;
	box-sizing: border-box;
	width: 16px;
	height: 16px;
	margin-left: 6px;
	font-size: 11px;
	font-weight: 700;
	line-height: 16px;
	text-align: center;
	text-transform: none;
	letter-spacing: 0;
	color: #fff;
	background: #3d8bfd;
	border-radius: 50%;
	cursor: help;
	vertical-align: middle;
	opacity: 0.8;
	transition: opacity 0.15s ease, transform 0.15s ease;
}
.et-tip-i:hover {
	opacity: 1;
	transform: scale(1.1);
}
/* 关掉主题自带的信息图标，避免和问号重复 */
.cbi-value-title.et-tip::before,
.cbi-value-description.et-tip::before,
.form-group label.et-tip::before {
	content: none !important;
	display: none !important;
}
/* ===== 浮层 ===== */
.et-tip-b {
	display: none;
	position: fixed;
	z-index: 3000;
	box-sizing: border-box;
	width: 320px;
	max-width: calc(100vw - 32px);
	padding: 8px 10px;
	margin: 0;
	font-size: 12px;
	font-weight: 400;
	line-height: 1.55;
	text-align: left;
	white-space: normal;
	color: #eceff1;
	background: #263238;
	border: 1px solid rgba(255, 255, 255, 0.14);
	border-radius: 8px;
	box-shadow: 0 8px 24px rgba(0, 0, 0, 0.45);
}
.et-tip-b.et-tip-show {
	display: block;
}
.et-tip-b a {
	color: #7cc7ff;
	text-decoration: underline;
}
/* 说明原文已搬进浮层，这一行不再占位 */
.et-tip-src {
	display: none !important;
}
/* 兜底：找不到可挂的标题时，问号就地变成行内 16px 图标 */
.et-tip-fb {
	display: inline-block !important;
	width: auto !important;
	margin: 0 0 0 6px !important;
	padding: 0 !important;
	font-size: 0 !important;
	line-height: 0 !important;
	background: none !important;
	border: 0 !important;
	/* 有些主题给说明加了 opacity，会让浮层叠不上 */
	opacity: 1 !important;
	vertical-align: middle !important;
	white-space: normal;
}
/* Map 的 description 只用来承载这段样式/脚本，不占高度 */
.cbi-map-descr {
	margin: 0 !important;
	padding: 0 !important;
	border: 0 !important;
	min-height: 0 !important;
}
</style>
<script>
(function () {
	var TIP_W = 320;   // 浮层宽度上限
	var GAP = 6;       // 问号与浮层的间距

	function hasClass(el, cls) {
		return !!el.className && (' ' + el.className + ' ').indexOf(' ' + cls + ' ') !== -1;
	}

	// 向上找最近的某类祖先
	function closestByClass(el, cls) {
		var n = el.parentNode;
		while (n && n.nodeType === 1) {
			if (hasClass(n, cls)) {
				return n;
			}
			n = n.parentNode;
		}
		return null;
	}

	// 同一行里直接子元素形式的 .cbi-value-title
	function findTitle(row) {
		for (var i = 0; i < row.children.length; i++) {
			if (hasClass(row.children[i], 'cbi-value-title')) {
				return row.children[i];
			}
		}
		return null;
	}

	// .form-group 里第一个有文字、且不是开关的 label
	function findGroupLabel(group) {
		var labels = group.getElementsByTagName('label');
		for (var i = 0; i < labels.length; i++) {
			if (hasClass(labels[i], 'switch')) {
				continue;
			}
			if (labels[i].textContent.replace(/\s+/g, '')) {
				return labels[i];
			}
		}
		return null;
	}

	function findAnchor(el) {
		var row = closestByClass(el, 'cbi-value');
		if (row) {
			var t = findTitle(row);
			if (t) {
				return t;
			}
		}
		var group = closestByClass(el, 'form-group');
		if (group) {
			var lb = findGroupLabel(group);
			if (lb) {
				return lb;
			}
		}
		return null;
	}

	// 摆位：贴在问号下方；右侧放不下就左移，底部放不下就翻到上方
	function place(icon, panel) {
		panel.style.visibility = 'hidden';
		var ir = icon.getBoundingClientRect();
		var w = Math.min(TIP_W, window.innerWidth - 32);

		panel.style.width = w + 'px';
		panel.style.top = '0px';
		panel.style.left = '0px';
		var h = panel.offsetHeight;

		var left = ir.left;
		if (left + w > window.innerWidth - 8) {
			left = window.innerWidth - 8 - w;
		}
		if (left < 8) {
			left = 8;
		}

		var top;
		if (ir.bottom + GAP + h <= window.innerHeight - 8 || ir.top - GAP - h < 8) {
			top = ir.bottom + GAP;
		} else {
			top = ir.top - GAP - h;
		}
		if (top < 8) {
			top = 8;
		}

		panel.style.left = Math.round(left) + 'px';
		panel.style.top = Math.round(top) + 'px';
		panel.style.visibility = '';
	}

	function build(desc) {
		if (desc.getAttribute('data-et-tip') === '1') {
			return;
		}
		// 空说明（很多开关行会渲染一个空 description）不放问号
		if (!desc.textContent.replace(/\s+/g, '') && !desc.querySelector('img')) {
			return;
		}

		var anchor = findAnchor(desc);
		var fallback = !anchor;

		// 说明原文整体搬进浮层，<br>/<strong>/链接都保留
		var panel = document.createElement('div');
		panel.className = 'et-tip-b';
		panel.setAttribute('role', 'tooltip');
		while (desc.firstChild) {
			panel.appendChild(desc.firstChild);
		}

		var icon = document.createElement('span');
		icon.className = 'et-tip-i';
		icon.textContent = '?';
		icon.setAttribute('role', 'button');
		icon.setAttribute('tabindex', '0');
		icon.setAttribute('aria-label', '说明');

		if (fallback) {
			anchor = desc;
		}

		anchor.className += ' et-tip' + (fallback ? ' et-tip-fb' : '');
		anchor.setAttribute('data-et-tip', '1');
		anchor.appendChild(icon);
		document.body.appendChild(panel);

		desc.setAttribute('data-et-tip', '1');
		// 兜底时问号就挂在说明元素自身上，不能再加 et-tip-src，否则会把问号一起 display:none
		if (!fallback) {
			desc.className += ' et-tip-src';
		}

		var hideTimer = null;
		var pin = false;

		function open() {
			clearTimeout(hideTimer);
			panel.className = 'et-tip-b et-tip-show';
			place(icon, panel);
		}
		function close() {
			clearTimeout(hideTimer);
			panel.className = 'et-tip-b';
		}
		function later() {
			clearTimeout(hideTimer);
			// 留一点时间让指针从问号移到浮层上
			hideTimer = setTimeout(function () {
				if (!pin) {
					close();
				}
			}, 140);
		}

		icon.addEventListener('mouseenter', open);
		icon.addEventListener('mouseleave', later);
		panel.addEventListener('mouseenter', function () {
			clearTimeout(hideTimer);
		});
		panel.addEventListener('mouseleave', later);
		icon.addEventListener('focus', open);
		icon.addEventListener('blur', later);
		icon.addEventListener('click', function (e) {
			// 标题本身是 <label>，不拦下来会顺带切换/聚焦对应输入框
			e.preventDefault();
			e.stopPropagation();
			pin = !pin;
			anchor.className = pin
				? anchor.className + ' et-tip-pin'
				: anchor.className.replace(/\s*et-tip-pin/g, '');
			if (pin) {
				open();
			} else {
				close();
			}
		});
		icon.addEventListener('keydown', function (e) {
			if (e.key === 'Enter' || e.key === ' ') {
				e.preventDefault();
				icon.click();
			}
		});
		// 点页面其它位置收起（点问号时已 stopPropagation，不会走到这里）
		document.addEventListener('click', function () {
			pin = false;
			anchor.className = anchor.className.replace(/\s*et-tip-pin/g, '');
			close();
		});
		// 滚动/缩放时跟着走，避免浮层停在旧位置
		function follow() {
			if (panel.className.indexOf('et-tip-show') !== -1) {
				place(icon, panel);
			}
		}
		window.addEventListener('scroll', follow, true);
		window.addEventListener('resize', follow);
	}

	function init() {
		var list = document.querySelectorAll('.cbi-value-description, .form-group .description');
		for (var i = 0; i < list.length; i++) {
			build(list[i]);
		}
	}

	if (document.readyState === 'loading') {
		document.addEventListener('DOMContentLoaded', init);
	} else {
		init();
	}
})();
</script>
]=]

return html
