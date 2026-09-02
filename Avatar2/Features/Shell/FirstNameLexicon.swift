// Voornamen-lexicon voor de offline naamherkenning (PortraitNameGuess).
// Gebundeld, geen netwerk, geen permissies. Een herkende voornaam is het
// zekerheids-signaal dat een token-reeks écht een persoonsnaam is; wat erna
// komt geldt als achternaam (tussenvoegsels inbegrepen). Ontbreekt elke
// voornaam, dan beslist een woordenboek-check (NLTagger) of de overgebleven
// woorden gewone woorden zijn ("man beard" → geen naam) of onbekend ("looijen"
// → achternaam, blijft staan).
//
// Samengesteld uit veelvoorkomende voornamen: NL (incl. Fries en modern), EN
// (UK/US), DE, FR, ES/IT/PT, PL, Scandinavisch, TR, Arabisch/Marokkaans,
// Surinaams/Hindoestaans, Chinees/Japans/Koreaans/Vietnamees (geromaniseerd).
// Opslag: kleine letters, accenten gevouwen (zoë → zoe); matching idem.
// Ruiswoorden en tussenvoegsels uit PortraitNameGuess zijn eruit gehouden.
// Aanvullen = een woord toevoegen aan de lijst hieronder.

import Foundation

enum FirstNameLexicon {

    /// Gevouwen (kleine letters, accentloos) lookup.
    static func contains(_ token: String) -> Bool {
        names.contains(fold(token))
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
    }

    static var count: Int { names.count }

    private static let names: Set<String> = Set(raw.split(whereSeparator: \.isWhitespace).map(String.init))

    // swiftlint:disable line_length
    private static let raw = """
    aafke aaliyah aaltje aaron aarti abbey abdel abdelkader abdul abdullah abel abigail abraham ada
    adalyn adalynn adam addison adele adeline aditya adriaan adrian adriana afonso agata agatha agnes
    agnieszka ahmad ahmed ahmet aicha aidan aiden aileen aisha ajay akari alain alaina alan alana alba
    albert alberto albie aldo aleid alejandro aleksandra alessandro alessia alessio alex alexa
    alexander alexandra alexandre alexis alfie alfred ali alice alicia alicja alida alina aliyah
    allison alma alvaro alvin alyssa amalia amanda amandine amara amaya amber amelia amelie amin amina
    amine amir amira amit amos amparo amy ana anais ananya anas anastasia anders andre andrea andreas
    andres andrew andries andrzej angel angela angeles angelika angelique angelo angus anh anil anita
    anja anjali anke ann anna annabel annabelle anne anneke annelien annelies anneliese annemarie
    annemiek annet annette annie annika anouk ansgar anthony antje antoine anton antonia antonietta
    antonio antoon aoi april arabella archie arend aria ariana ariane arianna arianne arie ariel arjan
    arjen arjun arlene armin arno arnold arthur artur arun arvid arya asha asher ashley ashok ashton
    asma asmaa astrid athena aubree aubrey audrey august auke aukje aurelie aurora austin autumn ava
    avery axel ayla ayman ayoub ayse ayumi babette bailey barbara barry bart bartosz bas basil bastiaan
    bastian beata beatrice beatrix beatriz beau belinda bella ben bengt benjamin bennett benoit bente
    bep berber bernard bernd bernice bert bethany bettina betty beulah beverly bianca bibi bilal billy
    birgit birgitta birgitte bjorn blake blanca blanche bo bob bobby bogdan bonnie boris boudewijn
    boukje boyd bozena brad bradley brahim bram brandon brenda brent brett brian brianna bridget
    brielle brigitte britt brittany brooke brooklyn brooks bruce bruno bryan bulent burak busra byron
    caleb callie calvin cameron camila camille can candace carel carina carl carla carlijn carlo carlos
    carmela carmen carol carolien carolin carolina caroline carolyn carsten carter cas casper cassandra
    catarina caterina catherine cato cecil cecile cecilia cedric celeste celia celine cem cengiz chad
    chantal charlene charles charlie charlotte chase chen cheryl chester chiara chloe chris christa
    christer christiaan christian christina christine christoph christophe christopher christy cihan
    cindy claire clara clarissa clark claudia clement clifford clinton clyde cobie cody colin colleen
    colton conceicao concepcion connor conrad constance constantijn cooper cora corey corine corinne
    cornelia cornelis craig cristina crystal curtis cynthia czesław daan dagmar daiki daisy dale damian
    damien damon dana dani daniel daniela danielle danuta daphne dariusz darren david davide dawid dawn
    dean deanna deborah debra declan deepa deepak delano delilah delores delphine demi denise deniz
    dennis derek derk derya desiree desmond detlef dev dexter dhruv diana diane didier diederik diego
    dieter dieuwke dilek dina dinesh diogo dionne dirk divya diya do-yun dogan dolores domenico dominic
    dominik dominique donald donna donny dora doreen dorien doris dorota dorothea dorothee dorothy
    dorthe douglas dounia doutzen douwe driss duane duarte duc duncan dwayne dylan earl easton ebba
    ebru ece eckhard eden edgar edith edmund edna eduard edward edwin edyta eef eefje egbert eileen
    elaine elbert eleanor elena eleonora eli eliana elias elif elijah elin eline elisa elisabeth elise
    eliza elizabeth elke ella ellen elliana ellie elliot ellis elly elma elmer elodie eloise els elsa
    elsbeth elsie elton elzbieta emanuele emerson emersyn emery emi emiel emil emile emilia emilie
    emily emine emma emmanuel emmett emre enrique ercan erdem eren eric erica erik erika erin erkan
    ernest ernestine ernst ertugrul esma esme esmee esra estelle esther ethan ethel eugene eunice eva
    evan evelien evelyn everett everleigh everly evert evi evie ewa ewelina ewout ezekiel ezra fabian
    fabien fabio fabrice faisal faith famke fang fatih fatima fatma fay febe fedde federica federico
    felicia felix fem femke feng fenna fenne ferdinand ferhat feride fernanda fernando fien fiene filip
    filiz finley finn fletcher fleur floor floortje flora florence florian floris floyd folkert forrest
    frances francesca francesco francien francisca francisco franco francois francoise frank frankie
    franklin frans franz franziska frauke fred freda freddie frederic frederick frederik frederique
    fredrik freek freja freya friedrich furkan gabriel gabriele gabriella gael gail ganesh gang garrett
    gary gavin geert geertje geeta geke gemma gene genesis genevieve genowefa geoffrey georg george
    georgia gerald geraldine gerard gerben gerda gerhard gerlof gerrit gert gertrude gianna gijs
    gijsbert gilbert gilles gina ginevra ginger giorgio giovanna giovanni girish gisela gita gitte
    giulia giuseppe giuseppina gizem gladys glen glenda glenn gloria gokhan goncalo gonzalo gordon
    gottfried govert grace gracie graham grant grayson gregor gregory greta gretchen greyson grzegorz
    gudrun guido guillaume gul gulsum gunnar gunter gustaaf gustav gwen gwendolyn ha-eun ha-jun
    hadewych hadley hafsa hailey hajar hakan halil halina hamza hana hanan hanane hanife hank hanna
    hannah hanne hanneke hannelore hans hao harish harm harmen harmony harold harper harriet harrison
    harry hartmut haruto harvey hasan hassan hatice hattie havva hazel heather hector hedwig heidi
    heike hein heinrich heinz heleen helen helena helene helga helle helmer helmut hendrik henk hennie
    henning henriette henrik henry henryk herbert herman herve hessel hester hetty hicham hidde hilda
    hilde hina hiroshi hoa hoang hoda holger holly homer hope horst howard hua hubert huda hudson hugo
    hui huib hulya humphrey hunter huong huseyin hussain hussein huub huy ian ibrahim ida idris ids
    ignacio ijsbrand ikram ilias ilona ilse ilyas imad iman imane imke imogen ina ineke ines inge inger
    ingo ingrid inmaculada irena irene iris irma irmgard irving isa isaac isabel isabella isabelle
    isaiah isak ishaan isla ismail ivan ivo ivonne ivy iwona izabela jaap jace jacek jack jackie
    jackson jacob jacqueline jacques jade jadwiga jaime jake jakub jamal james jamie jan jan-jaap
    jan-willem jana janelle janet janice janina janine janna janneke jantine janusz jara jared jarosław
    jasmijn jasmin jasmine jason jasper javier jaxon jayden jean jeanet jeanette jeanine jeanne jeffrey
    jelle jelmer jelte jenna jennifer jenny jens jenson jeremy jeroen jerome jerry jerzy jesper jesse
    jessica jessie jesus jet jetske jette ji-ho ji-min ji-woo jian jie jill jim jimmy jing jip jitendra
    joachim joan joana joanna joanne joao joaquin job jocelyn jochem jochen jodie joe joel joelle joep
    joerg johan johanna johannes john johnny joke jolanda jolanta jonah jonas jonathan joost jordan
    jordi jordy jordyn jorg jorge joris jorn jort jos jose josef josefa josefine joseph josephine
    joshua josiah josiane josie joy joyce jozef juan juana juanita judd jude judith judy julia julian
    juliana julie julien juliet juliette julius jun jun-seo june jurgen jurre jurriaan justin justyna
    jutta jørgen kadir kai kajal kamal kamil kaori kara karan kareem karel karen karim karin karina
    karl karl-heinz karlijn karolina karst kasper katarzyna kate katharina katherine kathleen kathryn
    kathy katie katja katrin kavita kawtar kay kayla kaylee kayleigh kazimiera kazimierz kazuki kees
    keith kelly kelsey kelvin kemal kendall kendra kenji kennedy kenneth kenta kerem kerry kerstin
    kevin khadija khaled khalid khloe kiki kim kimberly kinga kingston kinsley kiran kirk kirsten
    kishore klaas klaas-jan klara klaudia klaus knut koen komal konrad koos kris krishna kristen
    kristin kristina krystyna krzysztof kubra kumar kurt kyle kylie lacey laila lakshmi lambert lan
    lance landon lara larry lars latifa latoya laura laure lauren laurence laurens laurent laurie
    lawrence laxmi layla lea leah lee lei leif leila leilani lena lene lennart lente leo leon leonard
    leonardo leonie leonor leontine leroy leslie lester leszek levi lex leyla liam lianne lidewij lidia
    lieke lies liesbeth liesje lilian liliana lillian lillie lilly lily lin lina lincoln linda lindsay
    ling linh linnea lionel lisa lisanne lise liv lizzy lloyd lodewijk loeki loes logan loic lois lola
    london londyn lone long lonneke lonnie lorena lorenzo loretta lorraine lothar lotte lottie lou
    loubna louis louise lourens lovisa luc luca lucas lucia luciano lucie lucille lucy lucyna ludo
    ludovic ludovica ludvig ludwig luella luigi luis luisa lukas luke luna lutz luuk luus lydia lyla
    lyle lynn maaike maarten mabel maciej mackenzie madalena madeleine madelief madeline madelon
    madelyn madison mads magali magda magdalena maggie magnus mahesh mahmut mai maike maikel maisie
    maja malcolm malika malin malte malthe manal mandy manfred manoj manon manouk manuel manuela mara
    marc marcel marcia marcin marco marcos marek margaret margareta margarita margaux margit margot
    margreet margriet marguerite maria mariam marian mariana marianna marie marieke marije marijke
    marijn marilyn marina marinus mario marion marit marius mariusz marjan marjet marjolein marjolijn
    marjorie mark markus marleen marlene marlies marloes marlou marshall mart marta martha marthe
    martijn martin martina martine marvin marwan mary maryam marzena mason mateo mateusz mathias
    mathieu mathijs mathilde matilda matilde mats matteo matthew matthias matthieu matthijs maud
    maureen maurice maurits maverick maxime maximilian maxine maya małgorzata meena mees megan mehdi
    mehmet mei meike melanie melek melis melissa melody melvin menno mercedes meredith merel mert merve
    meryem mette mia michael michał michel michele michelle michiel mick mickael mieczysław mieke mies
    miguel mikael mike mikkel mila milan mildred miles millie milo milou milton min-jun min-seo ming
    minh minke minnie miranda miriam mirjam mirosław mirthe misty mitchel mitchell mohamed mohammad
    mohammed mohan molly mona monica moniek monika monique montserrat monty morgan moritz morris mounir
    muhammad mukesh murat muriel murray mustafa mya myra myrthe myrtle nabil nadia nadine naima najat
    nancy nanda naoki naomi narayan naresh nasser natalia natalie nathalie nathan nathaniel nawal nazlı
    neeltje neha neil nel nele nell nelleke nellie nelson nerea nevaeh nezha nguyen nicholas nick nico
    nicola nicolaas nicolas nicole nidhi niek niels nienke nikhil nikki niklas nils nilufer nina nisha
    nisrine noa noah noe noel noelia nolan noor noortje nora norah norbert norma norman nour nova nuno
    nur nuray nuria nurten nynke oceane odette odile oguz okke olaf ole olga olive oliver olivia
    olivier ollie olof omar omer onno onur oona opal orhan orlando orville osama oscar oskar osman otis
    otto oussama owen ozlem pablo paige paisley pamela paola paolo parker pascal patricia patrick
    patrycja paul paula paulina pauline paulo paweł pearl pedro peggy penelope penny pepijn per percy
    perry peter petra peyton philip philipp philippe phoebe phyllis pia pien pierre piet pieter
    pieter-jan pietro pilar pim ping piotr pip piper pleun polly pooja poppy pradeep prakash pramod
    preeti preston priscilla priya przemysław puck puk pınar qiang quentin quinn quint quinten rachel
    rachid rachida radha rae raelynn rafael rafał rahma rahul rainer raj rajesh rakesh ralf ralph ram
    ramazan ramesh ramon ramona rana randall randy rania ranjit raphael raquel rashid rasmus raul ravi
    raymond reagan rebecca recep reda redouan redouane reese regilio regina reginald reid reinhard
    reinier reinout rekha rembrandt remco remi ren renata renate rene rens renske renu reuben rex rhett
    rhonda ria rianne ricardo riccardo richard rick rieke rik rikke riley rin rina rinse rita rixt riya
    rob robert roberta roberto robin robyn rocio rodney rodrigo roel roelof roger rogier rohan rohit
    roland rolf romain roman romeo romy ron ronald ronja ronnie roos rory rosa rosalie rosalind rosanne
    rosario rose rosemary rosie ross rowan roxanne roy ruben ruby rudi rudiger rudolf rudy rufus rui
    rupert russell rutger ruth ruud ryan ryder rylee ryleigh ryo ryszard saar saartje sabine sabrina
    sachin sadie safa safae saga said saida sakura salih sally salma salvador salvatore sam samantha
    sami samir samira samuel sana sanaa sandeep sander sandra sandrine sanjay sanna sanne santiago sara
    sarah saskia satish satoshi savannah sawyer scarlett scott sean sebastiaan sebastian sebastien seda
    seema sef selena selim selin selma sem senna seo-jun seo-yeon serdar serenity serge sergio serife
    serkan sevgi sevim shankar shannon shanti sharon sheila shelby shelley sherman sherry shirley shiva
    shreya sibel sidney sieb siegfried siem sien sienna sietse sietze signe sigrid siham sil silas
    silke silvia simon simona simone sinan siri sita sixten sjaak sjef sjoerd sjors sjoukje sky skylar
    sloane sneha sofia sofiane sofie solange songul sonia sonja sonny sophia sophie soraya soren sota
    souad soufiane spencer stacey stacy stan stanisław stanisława stanley stef stefan stefania stefanie
    stefano steffen stella stephane stephanie stephen sterre steven stijn storm stuart su-bin sue
    suleyman sultan summer sunanda sunil sunita sunny suresh susan susana susanne suus suzanne sven
    svenja swati sybren sydney sylvain sylvester sylvia sylvie sylwia søren sławomir tabitha tadeusz
    takeshi tamara tanja tanya tao tara tarik tariq taro tars tasha taylor teagan teddy teije teresa
    terrence terry tess tessa teun teuntje thanh thea thei thelma theo theodoor theodor theodore
    theresa thibault thierry thijmen thijs thirza thomas thorsten thu tiago ties tiffany tijn tijs
    tilde till tilo tim timo timothy tina tineke tirza titia tjalling tjeerd tobias toby todd toine
    tolga tom tomas tomasz tommaso tommy ton toni tonnie tony torben torsten tracy travis trevor
    trinity troy trudy tuan tucker tugba tuva twan tycho tyler tyrone udo ufuk ulf ulla ulrich uma umar
    umut ursula urszula usha ute uwe valentijn valentin valentina valeria valerie vandana vanessa varun
    veerle velma vera verena vernon veronica veronique vic vicente vicki victor victoria vigo vijay
    vikram viktor vincent vincenzo vinod viola violet virginia virginie vishal vittoria vivian volkan
    volker wade wafa waldemar walid wallace walter wanda warren wayne wei wendy wenzel werner wesley
    wessel weston whitney wibe widad wiebe wieke wiesław wiesława wietse wietske wilbert wilbur wilco
    wilfred wilhelm willem willem-jan willemijn william willie willow wilma wilson wim winfried
    winifred winston wojciech wolfgang wolfram woodrow wout wouter wyatt wybe władysław xander xavier
    xia ximena xin xiu yan yang yann yannick yara yasemin yash yasin yasmin yasmine yassin yassine
    ye-jin yfke ying ylva ymke yoeri yolanda yong yorick younes younous youri yousef yousra youssef yue
    yui yuki yuna yunus yuri yusuf yuto yves yvette yvonne zachary zahra zainab zakaria zakariya zane
    zara zayden zaynab zbigniew zdzisław zeger zehra zelda zeynep zhen zhi zineb zoe zoey zofia zohra
    łukasz
    """
    // swiftlint:enable line_length
}
