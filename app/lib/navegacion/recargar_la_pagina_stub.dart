/// NO HAY PAGINA QUE RECARGAR. Es lo que se compila en la APK, en el escritorio
/// y en las pruebas, que corren en la maquina virtual.
///
/// No lanza a proposito. El aviso de version nueva ya decide por destino —en el
/// aparato ofrece instalar, nunca recargar—, asi que llegar aqui significaria
/// que esa decision se rompio; y un aviso que revienta la aplicacion es peor
/// que un aviso que no hace nada. La prueba que vigila la decision es
/// «en la APK el aviso NO dice recargar».
Future<void> recargarLaPagina() async {}
