(() => {
  "use strict";
  const $ = (id) => document.getElementById(id);
  const form = $("config-form");
  const output = $("output");
  const status = $("status");
  const val = (id) => $(id).value.trim();
  const num = (id) => Number($(id).value);
  function generate() {
    if (!form.reportValidity()) return null;
    const profile = val("profile").replace(/[\r\n]/g, " ").slice(0, 60);
    const serial = val("serial");
    const x = num("xsize"), y = num("ysize"), z = num("zsize");
    const velocity = num("velocity"), accel = num("accel");
    const step = val("stepx"), dir = val("dirx"), enable = val("enablex"), endstop = val("endstopx");
    const hasPins = step && dir && enable && endstop;
    const lines = [
      "# Miracle Klipper — brouillon généré localement",
      "# Profil : " + profile,
      "# IMPORTANT : vérifiez chaque valeur selon la documentation de votre imprimante et de votre carte.",
      "# Ne démarrez pas Klipper avant d'avoir complété et validé toutes les sections matérielles.",
      "",
      "# MCU : décommentez et confirmez le chemin détecté sur votre machine.",
      "[mcu]",
      serial ? "serial: " + serial : "# serial: /dev/serial/by-id/REMPLACER_PAR_LE_PORT_REEL",
      "",
      "# Cinématique sélectionnée : " + val("kinematics"),
      "# Les broches, pas/mm, sens moteurs, endstops, chauffe et extrudeur doivent être complétés.",
      "# Ce générateur ne peut pas déduire ces valeurs de manière sûre.",
      "",
      "[printer]",
      "kinematics: " + val("kinematics"),
      "max_velocity: " + velocity,
      "max_accel: " + accel,
      "max_z_velocity: 10",
      "max_z_accel: 100",
      "",
      "# Enveloppe mécanique indiquée par l'utilisateur : X=" + x + " mm, Y=" + y + " mm, Z=" + z + " mm",
      "# Les limites min/max des axes doivent être adaptées aux endstops et à l'origine réelle.",
      "",
      "[virtual_sdcard]",
      "path: ~/printer_data/gcodes",
      "",
      "[display_status]",
      "[pause_resume]",
      "",
      "# --- À compléter avant utilisation ---",
      "# [stepper_x] : step_pin, dir_pin, enable_pin, rotation_distance, microsteps, endstop_pin, position_endstop, position_max",
      "# [stepper_y] : mêmes paramètres selon la cinématique et la carte",
      "# [stepper_z] : mêmes paramètres, avec vérification particulière des limites mécaniques",
      "# [extruder] : heater_pin, sensor_type, sensor_pin, control, nozzle_diameter, filament_diameter, rotation_distance",
      "# [heater_bed] : heater_pin, sensor_type, sensor_pin et limites thermiques adaptées",
      "# [safe_z_home] / [probe] / [bed_mesh] : uniquement si le matériel est présent et ses offsets mesurés",
      "# [fan] / [heater_fan] : selon le câblage réel",
      "",
      "# Récapitulatif des broches renseignées dans le formulaire (non validées électriquement) :",
      "# stepper_x step_pin: " + (step || "À DÉFINIR"),
      "# stepper_x dir_pin: " + (dir || "À DÉFINIR"),
      "# stepper_x enable_pin: " + (enable || "À DÉFINIR"),
      "# stepper_x endstop_pin: " + (endstop || "À DÉFINIR"),
      "# Sonde choisie : " + val("probe"),
      "# Extrudeur choisi : " + val("extruder"),
      "",
      "# Statut : " + (hasPins ? "broches X renseignées mais à vérifier" : "configuration incomplète — broches X à renseigner"),
      "# Ce fichier est un point de départ pédagogique, pas une configuration prête à imprimer."
    ];
    return lines.join("\n") + "\n";
  }
  function preview() {
    const config = generate();
    if (config === null) return;
    output.value = config;
    status.textContent = "Aperçu généré. Vérifiez les broches, les capteurs, les limites et les paramètres moteurs avant utilisation.";
    status.className = "status warn";
  }
  $("preview-btn").addEventListener("click", preview);
  form.addEventListener("submit", (event) => {
    event.preventDefault();
    const config = generate();
    if (config === null) return;
    output.value = config;
    const blob = new Blob([config], { type: "text/plain;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = "printer.cfg";
    document.body.appendChild(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(url);
    status.textContent = "Fichier téléchargé. Il s'agit d'un brouillon à compléter et valider avant démarrage.";
    status.className = "status warn";
  });
  $("copy-btn").addEventListener("click", async () => {
    if (!output.value) preview();
    if (!output.value) return;
    try {
      await navigator.clipboard.writeText(output.value);
      status.textContent = "Configuration copiée dans le presse-papiers.";
      status.className = "status ok";
    } catch (_) {
      output.focus();
      output.select();
      status.textContent = "Copie automatique indisponible : utilisez Ctrl+C après la sélection.";
      status.className = "status warn";
    }
  });
  preview();
})();