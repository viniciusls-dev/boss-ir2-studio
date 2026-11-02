# Integração USB do IR-2

## Fontes e limites

Implementação Swift independente. Os primeiros comandos de consulta foram corroborados pelo projeto [Gdadamo/boss_ir2_controller](https://github.com/Gdadamo/boss_ir2_controller), commit `694a6bce4bf0931630434dfd81dffdc245ddd365`, e pelos metadados do IR-2 IR Loader instalado no Mac (`product_setting.js` e `address_map.js`, versão declarada 1.0.0/build 0013). Não distribuímos código, IRs ou recursos do Loader.

Captura local de leitura em 1 de novembro de 2026: dispositivo USB BOSS, vendor `0x0582`, product `0x02ED`; fonte e destino Core MIDI `IR-2`.

## Mensagens

- Identidade universal: `F0 7E 7F 06 01 F7`.
- Resposta observada: `F0 7E 10 06 02 41 09 05 00 00 00 00 00 00 F7`.
- Cabeçalho específico: `F0 41 10 01 05 09`.
- RQ1 (leitura): comando `11`, endereço de 4 bytes, tamanho de 4 bytes, checksum, `F7`.
- DT1 (dados/escrita): comando `12`, endereço de 4 bytes, dados de 7 bits, checksum, `F7`.
- Checksum Roland: complemento da soma de endereço + dados/tamanho, módulo 128.

| Bloco | Endereço | Bytes |
|---|---|---:|
| Canal selecionado (0 verde, 1 vermelho) | `00 00 00 00` | 1 |
| Ajustes do canal ativo | `20 00 00 00` | 7 |
| Canal verde | `21 00 00 00` | 7 |
| Canal vermelho | `22 00 00 00` | 7 |

Offsets de cada patch: Bass 0, Middle 1, Treble 2, Level 3, Gain 4, Ambience 5, amplificador 6. Controles contínuos: 0–127. Amplificador: 0–10, na ordem CLEAN, TWN, TWEED, DIAMOND, CRUNCH, BRIT, HI-GAIN, SLDN, BROWN, MODDED, RFIER.

Dados efetivamente retornados pelo equipamento conectado:

- Verde: `40 60 49 5C 00 42 00`.
- Vermelho: `00 67 29 4F 77 65 02`.
- Seleção: `00`.

Isso confirma a leitura direta dos dois canais sem mudar o canal ativo. A escala numérica está identificada; não se presume linearidade acústica nem correspondência exata com ângulos do botão físico.

## Projeto da comunicação

Somente um pedido pendente por sessão, identidade validada antes das consultas, checksum e endereço conferidos, reconstrução de SysEx fragmentados e timeout de 2 segundos. A escrita se limita a um parâmetro conhecido ou à seleção de canal; toda alteração exige releitura. Nenhum comando de firmware, reset, restauração completa ou gravação de IR é oferecido por esta integração.

O Core MIDI entrega bytes em uma thread própria; os buffers são copiados antes de retornar e processados na main actor. O transporte usa as funções MIDI 1.0 para os endpoints do driver existente.

## Resultados adicionais no hardware

A escrita em `21…`/`22…` muda a memória do canal, mas não necessariamente o bloco que está produzindo o som (`20…`). Foi observado Gain armazenado = 1 com Gain ativo = 0. Por isso:

- A leitura obtém seleção antes/depois dos blocos e usa o bloco ativo para o canal em uso. Repete uma vez se houver troca de canal no meio da leitura.
- A escrita confirma o campo armazenado e, se o canal estiver ativo, atualiza e relê também `20 00 00 <offset>`. Uma troca de canal concorrente detectada interrompe a operação.
- O teste corrigido confirmou Gain ativo e armazenado 0 → 1 → 0, preservando todos os demais parâmetros.
- Trocar o campo de seleção isoladamente não carrega o som. A sequência validada foi DT1 em `00 00 00 00` com o canal, seguida de DT1 em `7F 00 01 00` com **dois bytes `00 <canal>`**, espera de 120 ms e releitura da seleção e do patch ativo. A troca verde → vermelho → verde foi confirmada com os valores integrais dos dois patches preservados. Os testes recusam sucesso se o som ativo não corresponder ao canal solicitado.

A seleção/edição não é uma transação atômica com movimentos físicos simultâneos; o software verifica a seleção após operações no bloco ativo e desabilita a edição ao detectar inconsistência. Falhas de escrita não são repetidas automaticamente. Atualize a leitura antes de retomar.

## Validação da interface

Na mesma unidade conectada, a interface foi usada para enviar Gain verde 0 → 1 → 0. Um segundo cliente de leitura confirmou o valor no bloco ativo. Também foram conferidos os botões Ativar Vermelho/Verde, captura dos dois canais como preset `Original do pedal`, aplicação desse preset e desconexão/reconexão em modo de leitura. Ao final, os dois patches permaneceram iguais aos valores anteriores aos testes e o canal ativo voltou ao verde.

A biblioteca anterior foi preservada. O preset capturado usa escala `pedal127`, mantendo exatamente inclusive o valor vermelho 119. A atualização automática foi observada na interface e também reage a mensagens recebidas; não foi medido um prazo de gravação permanente nem realizada uma nova medição física do ângulo dos potenciômetros.

## Canal selecionado não é estado ligado/bypass

O usuário relatou que o CHECK permanecia apagado durante os testes. Os testes anteriores comprovaram dados internos e correspondência entre seleção, memória e buffer `20…`; não houve observação física do LED nem teste auditivo. A expressão “bloco que está produzindo o som” acima deve ser entendida como buffer de edição atual, que também pode existir com o efeito em bypass.

Conforme o manual oficial (descrição do CHECK e footswitch), o LED fica apagado com o efeito desligado/bypass. A integração ainda não lê nem controla esse estado. A interface passa a mostrar SELECIONADO em vez de EM USO e Selecionar em vez de Ativar. Isso corrige a interpretação da evidência; não acrescenta controle de bypass nem certifica o LED. A confirmação física depende do usuário.

## Atualizações por eventos e menus estáveis

O usuário reproduziu o recolhimento do submenu de amplificadores a cada leitura de 3 segundos. A inspeção da interface confirmou que o submenu perdia sua seleção após a leitura. Um teste de regressão demonstrou que uma única notificação de knob provocava cinco novas consultas e transições de `busy`.

O polling periódico foi removido. Depois da identidade, a sessão envia `7F 00 00 01 = 01`, o modo volátil de comunicação do editor usado pelo Loader para habilitar relatórios. O app processa diretamente as mensagens DT1 válidas, sem uma nova leitura para cada mensagem. Não desliga esse modo ao fechar, para não interromper outros editores que possam compartilhar o dispositivo.

Mensagens de um mesmo burst são agrupadas por 12 ms. A seleção final é resolvida antes de atribuir o buffer ativo, pois um recall pode enviar `20…` antes do campo de seleção. Valores idênticos não publicam mudanças na interface. Mensagens inválidas são ignoradas sem aplicar um patch parcial. Durante uma operação explícita, os eventos são incorporados ao resultado verificado, preservando alterações recebidas enquanto o pedido estava pendente.

Permanecem as leituras completas ao conectar, ao atualizar manualmente e ao concluir um envio; releituras de confirmação de escrita também permanecem. A ausência de mensagens não é tratada como desconexão, pois um pedal parado pode permanecer silencioso. A conexão física continua monitorada pelo Core MIDI.
