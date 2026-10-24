# Primeiros passos

O TTS Mod Vault lê as pastas `Mods` e `Saves` do Tabletop Simulator, mostra cada mod, jogo salvo e objeto salvo com o estado dos seus arquivos de assets e permite baixar os arquivos que faltam, criar backups `.ttsmod` e restaurá-los.

- Defina as pastas em Configurações → Pastas. A pasta de backups é opcional, mas é necessária para que o estado dos backups seja lembrado entre as execuções.
- A biblioteca é indexada ao iniciar; clique em Atualizar na barra lateral depois de alterar arquivos fora do aplicativo. "Limpar o cache do Vault" relê todos os arquivos JSON.
- Mods, Jogos salvos, Objetos salvos e Backups são abas acima da lista. Objetos salvos aparecem quando ativados em Configurações → Recursos, e Backups quando uma pasta de backups está definida.

# Biblioteca

- Clique com o botão esquerdo em um mod para ver os assets e as ações
- Clique com o botão direito em um mod para mais ações (baixar, fazer backup, abrir pasta, renomear, excluir, ...)
- Ctrl+clique (Cmd+clique no macOS) para selecionar vários mods para ações em massa
- Passe o mouse sobre o ícone de backup de um mod para ver a data do backup e o número de assets
- Passe o mouse sobre o seletor de tipo para ver quantos mods, jogos salvos e objetos salvos existem
- Pesquise, ordene e filtre pela barra de ferramentas; as ações em massa respeitam o texto da pesquisa e os filtros
- Teclado: Ctrl+F foca a pesquisa, F5 atualiza, Esc limpa a seleção, Delete remove o mod selecionado após uma confirmação

# Mod selecionado

O painel direito lista os assets do mod selecionado, agrupados por tipo. Cores das URLs:

- Vermelho: o arquivo do asset está faltando
- Verde: o arquivo do asset foi baixado
- Laranja: uma verificação de URL marcou a URL como inválida
- Destacada: a última URL em que você clicou

Ações:

- Clique com o botão esquerdo ou direito em uma URL para ver as opções (abrir, copiar, baixar, substituir, excluir o arquivo)
- Clique duas vezes na miniatura de um PDF para abrir o arquivo
- Baixar tudo: baixa todos os arquivos de assets que faltam. Os arquivos que ainda faltarem depois disso são verificados: a caixa de diálogo "Resultados da verificação do download" lista os domínios que não puderam ser acessados e as URLs que não funcionam. Desative isso em Configurações → Rede → Verificar arquivos que faltam após os downloads
- "3 faltando, 2 inválidas" em um cartão: faltam 3 arquivos e uma verificação de URLs constatou que 2 das URLs deles não funcionam, então esses arquivos não podem ser baixados
- Backup: cria um backup a partir dos arquivos de assets baixados
- Os assets de áudio podem ser excluídos globalmente em Configurações → Recursos, e essa opção pode ser substituída para cada mod pelo menu de contexto do mod

# Backups

- Backups são arquivos `.ttsmod` que contêm o JSON do mod, a imagem dele e todos os arquivos de assets baixados.
- O estado do backup compara o backup com o mod: atualizado, desatualizado (o JSON mudou depois do backup) ou número de assets diferente.
- Use Importar backups na barra lateral para restaurar arquivos na pasta Mods. Importar JSON adiciona um mod a partir de um arquivo JSON.
- O backup em massa oferece ignorar, substituir e substituir se estiver desatualizado, com a opção de excluir os arquivos do mod em seguida.

# Atualizar URLs

O recurso Atualizar URLs funciona substituindo o início das URLs, ou até URLs inteiras, do "Prefixo antigo" pelo "Novo prefixo".

Você pode digitar vários prefixos antigos separando-os com o símbolo `|` (barra vertical). Em Configurações → Predefinições de atualização de URLs você pode criar predefinições, que depois aparecem na caixa de diálogo Atualizar URLs.

Usando um único prefixo antigo:

- Prefixo antigo: `http://pastebin.com/raw.php?i=`
- Novo prefixo: `https://pastebin.com/raw/`

Se o seu mod contiver `http://pastebin.com/raw.php?i=1234` e `http://pastebin.com/raw.php?i=example`, elas serão atualizadas para `https://pastebin.com/raw/1234` e `https://pastebin.com/raw/example`.

Usando vários prefixos antigos:

- Prefixos antigos: `http://pastebin.com/raw.php?i=|http://pastebin.com/raw/|http://pastebin.com/`
- Novo prefixo: `https://pastebin.com/raw/`

Se o seu mod contiver `http://pastebin.com/raw.php?i=abcd`, `http://pastebin.com/raw/5678` e `http://pastebin.com/example2`, elas serão atualizadas para `https://pastebin.com/raw/abcd`, `https://pastebin.com/raw/5678` e `https://pastebin.com/raw/example2`.

# Oficina

- Baixe mods da Oficina Steam pelo ID ou pela URL na barra lateral; vários IDs podem ser digitados de uma vez.
- Atualizar pela Oficina baixa novamente o JSON de um mod que já existe. A opção de forçar sobrescreve um arquivo local mais novo.

# Solução de problemas

- O painel de log abaixo da lista registra cada operação e suas falhas; expanda-o para filtrar por nível e origem, pesquisar, copiar entradas ou limpá-lo. Clique em uma entrada para selecionar o mod dela.
- O arquivo de log `vault.log` fica ao lado do banco de dados. Abra-o pelo cabeçalho do painel de log ou pela aba Sobre; anexe-o aos relatórios de bugs.
- Nada aparece depois de mudar uma pasta? Clique em Atualizar. Ainda nada? Confira os caminhos das pastas em Configurações → Pastas e as subpastas excluídas.
- Downloads de URLs que funcionam falham quando muitos rodam ao mesmo tempo? Diminua os downloads simultâneos em Configurações → Rede.
- As verificações de URLs e a verificação após um download primeiro testam se cada domínio pode ser acessado. URLs em um domínio inacessível (fora do ar ou bloqueado na sua rede) não são marcadas como inválidas, e uma verificação de URLs com um domínio assim não é salva. Configurações → Rede → Verificar todos os domínios de mods e jogos salvos testa cada domínio usado pelos seus mods e jogos salvos.
