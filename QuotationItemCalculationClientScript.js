// ============================================================
// ERPNext v15 — Client Script for Quotation v3
// Doctype: Quotation
// ============================================================

let is_recalculating = false;

function fmt(val) {
    return flt(val, 2).toLocaleString("en-IN", { minimumFractionDigits: 2 });
}

function recalculate_all(frm) {
    if (is_recalculating) return;

    try {
        is_recalculating = true;

        if (!frm.doc.items || !frm.doc.items.length) return;

        let sub_total = 0;

        frm.doc.items.forEach(row => {
            const uom       = (row.uom || "").toLowerCase();
            const pcs_ctn   = flt(row.custom_pcsctn);
            const total_ctn = flt(row.custom_total_ctn);
            const price     = flt(row.rate);
            let value       = 0;

            if (uom === "pcs") {
                // PCS: total pieces × rate
                // total pieces = pcs_ctn × total_ctn
                if (pcs_ctn > 0 && total_ctn > 0 && price > 0) {
                    value = flt(pcs_ctn * total_ctn * price, 2);
                }
            } else if (uom === "square meter" || uom === "sqmtr" || uom === "sqm") {
                // Square Meter: area × total_ctn × pcs_ctn × rate
                const width_m  = flt(row.custom_width_mm) / 1000;
                const length   = flt(row.custom_length_mtr);
                if (width_m > 0 && length > 0 && pcs_ctn > 0 && total_ctn > 0 && price > 0) {
                    value = flt(width_m * length * pcs_ctn * total_ctn * price, 2);
                }
            } else {
                // Fallback for any other UOM — keep ERPNext's own amount
                value = flt(row.amount);
            }

            if (value > 0) {
                row.amount = value;
                sub_total += value;
            } else {
                sub_total += flt(row.amount);
            }
        });

        frm.refresh_field("items");

        // GST 18%
        const gst_amount = flt(sub_total * 0.18, 2);

        // Custom charges
        const transport  = flt(frm.doc.custom_transport_charges);
        const other      = flt(frm.doc.custom_other_charges);
        const net_amount = flt(sub_total + gst_amount + transport + other, 2);

        // Override all ERPNext total fields
        frm.doc.total                   = flt(sub_total, 2);
        frm.doc.net_total               = flt(sub_total, 2);
        frm.doc.base_total              = flt(sub_total, 2);
        frm.doc.base_net_total          = flt(sub_total, 2);
        frm.doc.total_taxes_and_charges = flt(gst_amount + transport + other, 2);
        frm.doc.grand_total             = net_amount;
        frm.doc.base_grand_total        = net_amount;
        frm.doc.rounded_total           = net_amount;
        frm.doc.rounding_adjustment     = 0;

        frm.refresh_field("total");
        frm.refresh_field("net_total");
        frm.refresh_field("base_total");
        frm.refresh_field("base_net_total");
        frm.refresh_field("total_taxes_and_charges");
        frm.refresh_field("grand_total");
        frm.refresh_field("base_grand_total");
        frm.refresh_field("rounded_total");
        frm.refresh_field("rounding_adjustment");

        // Override GST tax row
        if (frm.doc.taxes && frm.doc.taxes.length) {
            frm.doc.taxes.forEach(tax => {
                if (flt(tax.rate) === 18) {
                    tax.tax_amount                           = gst_amount;
                    tax.base_tax_amount                      = gst_amount;
                    tax.total                                = flt(sub_total + gst_amount, 2);
                    tax.base_total                           = flt(sub_total + gst_amount, 2);
                    tax.tax_amount_after_discount_amount     = gst_amount;
                }
            });
            frm.refresh_field("taxes");
        }

        // Summary bar
        const summary_html =
            `Sub Total: ₹${fmt(sub_total)} &nbsp;|&nbsp; ` +
            `GST (18%): ₹${fmt(gst_amount)} &nbsp;|&nbsp; ` +
            `Transport: ₹${fmt(transport)} &nbsp;|&nbsp; ` +
            `Other: ₹${fmt(other)} &nbsp;|&nbsp; ` +
            `<b>Net Amount: ₹${fmt(net_amount)}</b>`;

        let $bar = frm.layout.wrapper.find("#custom-summary-bar");
        if (!$bar.length) {
            frm.layout.wrapper.prepend(
                `<div id="custom-summary-bar" style="
                    background: #f0f4f8;
                    border-bottom: 1px solid #d1d8dd;
                    padding: 8px 16px;
                    font-size: 13px;
                    color: #333;
                "></div>`
            );
            $bar = frm.layout.wrapper.find("#custom-summary-bar");
        }
        $bar.html(summary_html);

    } catch(e) {
        console.error("Custom recalculate_all error:", e);
    } finally {
        is_recalculating = false;
    }
}

// Debounce
let recalc_timer = null;
function debounced_recalc(frm, delay = 300) {
    if (recalc_timer) clearTimeout(recalc_timer);
    recalc_timer = setTimeout(() => recalculate_all(frm), delay);
}


// ─── Quotation Item events ───────────────────────────────────

frappe.ui.form.on("Quotation Item", {
    custom_width_mm(frm)   { debounced_recalc(frm); },
    custom_length_mtr(frm) { debounced_recalc(frm); },
    custom_pcsctn(frm)     { debounced_recalc(frm); },
    custom_total_ctn(frm)  { debounced_recalc(frm); },
    rate(frm)              { debounced_recalc(frm); },
    uom(frm)               { debounced_recalc(frm); },
    qty(frm)               { debounced_recalc(frm); },
    items_remove(frm)      { debounced_recalc(frm); },
    items_add(frm)         { debounced_recalc(frm); }
});


// ─── Quotation (parent) events ───────────────────────────────

frappe.ui.form.on("Quotation", {
    refresh(frm)                  { debounced_recalc(frm); },
    onload(frm)                   { debounced_recalc(frm); },
    party_name(frm)               { debounced_recalc(frm, 800); },
    customer(frm)                 { debounced_recalc(frm, 800); },
    quotation_to(frm)             { debounced_recalc(frm, 800); },
    taxes_and_charges(frm)        { debounced_recalc(frm, 800); },
    tax_category(frm)             { debounced_recalc(frm, 800); },
    custom_transport_charges(frm) { debounced_recalc(frm); },
    custom_other_charges(frm)     { debounced_recalc(frm); },
    conversion_rate(frm)          { debounced_recalc(frm, 800); },
    after_save(frm)               { debounced_recalc(frm); }
});
